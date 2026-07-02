"""Build the "Кадры" feed for a user.

Rules (see analysis/mockups/memories/hybrid.html):
- Only ACTIVE/COMPLETED events with uploaded frames are considered.
- Single-album blocks come first (fresh at top).
- Collection blocks (by event_type, ≥2 albums) come after.
- Layout types are rotated: never two identical block types in a row.
- Tilted goes first if possible (most visually alive).
"""
import random
from collections import defaultdict
from uuid import UUID

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.domain.models import Event, EventStatus, Frame, FrameStatus
from app.domain.models.enums import EventType
from app.domain.schemas.memories import MemoriesOut, MemoryBlock, MemoryThumb
from app.infra import s3_client


# Layout weights — collages appear less often (they take more vertical space).
# Sum can be any positive number; we sample by relative weight.
# NOTE: collage_c is removed (looked bad in tests). Client is expected to
# render collage_a in randomly-mirrored orientation.
_LAYOUT_WEIGHTS: dict[str, int] = {
    "tilted":    40,   # самый частый — быстро листается
    "grid_6":    22,   # 6-грид с каруселью
    "collage_a": 14,   # 1 большой + 2 маленьких (client mirrors randomly)
    "collage_b": 8,    # 2×2 равных
    "collage_d": 9,    # центр-акцент
    "collage_e": 7,    # 1 big + 3 stack
}

# For grid_6 we need at least 6 thumbs; if not enough — fall back to tilted.
_MIN_THUMBS_PER_TYPE: dict[str, int] = {
    "tilted": 4,
    "collage_a": 3,
    "collage_b": 4,
    "collage_d": 5,
    "collage_e": 4,
    "grid_6": 6,
}

# Больше thumbs для листаемых блоков.
# tilted: 4×N карточек в стрипе; grid_6: 6×N страниц; коллажи: 3-5 «наборов».
_MAX_THUMBS_PER_TYPE: dict[str, int] = {
    "tilted": 24,     # 6 «страниц» по 4 карточки
    "collage_a": 12,  # 4 «набора» по 3 фото
    "collage_b": 12,  # 3 «набора» по 4 фото
    "collage_d": 15,  # 3 «набора» по 5
    "collage_e": 12,  # 3 «набора» по 4
    "grid_6": 30,     # 5 страниц по 6
}
_MAX_THUMBS_PER_BLOCK = 30

_EVENT_TYPE_TITLES: dict[EventType, str] = {
    EventType.WEDDING: "Свадьбы года",
    EventType.BIRTHDAY: "Дни рождения года",
    EventType.CORPORATE: "Корпоративы",
    EventType.PARTY: "Отлично оторвались",
    EventType.GRADUATION: "Выпускные",
    EventType.TRAVEL: "Путешествия",
    EventType.VACATION: "Отпуска",
    EventType.CONCERT: "Концерты",
}

_EVENT_TYPE_BADGE: dict[EventType, str] = {
    EventType.WEDDING: "Свадьба",
    EventType.BIRTHDAY: "День рождения",
    EventType.CORPORATE: "Корпоратив",
    EventType.PARTY: "Вечеринка",
    EventType.GRADUATION: "Выпускной",
    EventType.TRAVEL: "Путешествие",
    EventType.VACATION: "Отпуск",
    EventType.CONCERT: "Концерт",
    EventType.OTHER: "",
}


async def _fetch_thumbs_for_event(
    session: AsyncSession, event_id: UUID, limit: int
) -> list[MemoryThumb]:
    """Return up to `limit` thumb objects from an event, newest captured_at first."""
    stmt = (
        select(Frame.id, Frame.thumbnail_url, Frame.s3_key)
        .where(
            Frame.event_id == event_id,
            Frame.status == FrameStatus.UPLOADED,
        )
        .order_by(Frame.captured_at.desc())
        .limit(limit)
    )
    rows = (await session.execute(stmt)).all()
    thumbs: list[MemoryThumb] = []
    for frame_id, thumbnail_url, s3_key in rows:
        key = thumbnail_url or s3_key
        if not key:
            continue
        thumbs.append(
            MemoryThumb(
                url=s3_client.presign_get(key, expires_in=86400),
                event_id=event_id,
                frame_id=frame_id,
            )
        )
    return thumbs


async def _fetch_thumbs_for_events(
    session: AsyncSession, event_ids: list[UUID], limit: int
) -> list[MemoryThumb]:
    """For a collection: sample 1-2 recent frames per event, up to `limit` total."""
    thumbs: list[MemoryThumb] = []
    per_event = max(1, limit // max(1, len(event_ids)))
    for event_id in event_ids:
        chunk = await _fetch_thumbs_for_event(session, event_id, per_event + 1)
        thumbs.extend(chunk)
        if len(thumbs) >= limit:
            break
    return thumbs[:limit]


def _weighted_choice(rng: random.Random, exclude: str | None, thumbs_available: int) -> str:
    """Pick a layout by weight, avoiding `exclude` type and layouts that need more thumbs."""
    candidates: list[tuple[str, int]] = []
    for layout, weight in _LAYOUT_WEIGHTS.items():
        if layout == exclude:
            continue
        if thumbs_available < _MIN_THUMBS_PER_TYPE[layout]:
            continue
        candidates.append((layout, weight))
    if not candidates:
        # Fallback: anything that fits.
        for layout in _LAYOUT_WEIGHTS:
            if thumbs_available >= _MIN_THUMBS_PER_TYPE[layout]:
                return layout
        return "tilted"
    total = sum(w for _, w in candidates)
    r = rng.randint(1, total)
    running = 0
    for layout, weight in candidates:
        running += weight
        if r <= running:
            return layout
    return candidates[-1][0]


async def build_memories_feed(session: AsyncSession, user_id: UUID) -> MemoriesOut:
    # 1. Fetch all eligible events with frame counts.
    frame_count_sq = (
        select(Frame.event_id, func.count(Frame.id).label("cnt"))
        .where(Frame.status == FrameStatus.UPLOADED)
        .group_by(Frame.event_id)
        .subquery()
    )
    stmt = (
        select(Event, func.coalesce(frame_count_sq.c.cnt, 0).label("frames_count"))
        .join(frame_count_sq, frame_count_sq.c.event_id == Event.id, isouter=True)
        .where(
            Event.user_id == user_id,
            Event.status.in_((EventStatus.ACTIVE, EventStatus.COMPLETED)),
        )
        .order_by(Event.updated_at.desc())
    )
    rows = list((await session.execute(stmt)).all())

    events_with_frames = [(ev, cnt) for ev, cnt in rows if cnt and cnt > 0]
    if not events_with_frames:
        return MemoriesOut(blocks=[])

    # Deterministic per-user shuffle: same user, same feed order — until events change.
    rng = random.Random(str(user_id))

    # 2. Build single-album entries + collection entries, then interleave randomly.
    entries: list[tuple[str, MemoryBlock | None, Event | list[Event]]] = []

    for event, _cnt in events_with_frames:
        entries.append(("single", None, event))

    by_type: dict[EventType, list[Event]] = defaultdict(list)
    for event, _cnt in events_with_frames:
        if event.event_type != EventType.OTHER:
            by_type[event.event_type].append(event)
    for event_type, evs in by_type.items():
        if len(evs) < 2:
            continue
        entries.append(("collection", None, evs))

    # Random order, then choose layouts avoiding immediate repetition.
    rng.shuffle(entries)

    blocks: list[MemoryBlock] = []
    prev_layout: str | None = None

    for kind, _unused, payload in entries:
        if kind == "single":
            event = payload
            thumbs = await _fetch_thumbs_for_event(session, event.id, _MAX_THUMBS_PER_BLOCK)
            if len(thumbs) < 4:
                continue
            layout = _weighted_choice(rng, exclude=prev_layout, thumbs_available=len(thumbs))
            needed = _MAX_THUMBS_PER_TYPE.get(layout, _MIN_THUMBS_PER_TYPE[layout])
            blocks.append(
                MemoryBlock(
                    type=layout,  # type: ignore[arg-type]
                    kind="single",
                    title=event.title,
                    date_iso=event.updated_at or event.created_at,
                    albums_count=None,
                    event_id=event.id,
                    event_ids=[],
                    event_type=_EVENT_TYPE_BADGE.get(event.event_type, ""),
                    thumbs=thumbs[:needed],
                )
            )
        else:  # collection
            evs = payload
            title = _EVENT_TYPE_TITLES.get(evs[0].event_type, evs[0].event_type.value.capitalize())
            event_ids = [e.id for e in evs]
            thumbs = await _fetch_thumbs_for_events(session, event_ids, _MAX_THUMBS_PER_BLOCK)
            if len(thumbs) < 4:
                continue
            layout = _weighted_choice(rng, exclude=prev_layout, thumbs_available=len(thumbs))
            needed = _MAX_THUMBS_PER_TYPE.get(layout, _MIN_THUMBS_PER_TYPE[layout])
            blocks.append(
                MemoryBlock(
                    type=layout,  # type: ignore[arg-type]
                    kind="collection",
                    title=title,
                    date_iso=None,
                    albums_count=len(evs),
                    event_id=None,
                    event_ids=event_ids,
                    thumbs=thumbs[:needed],
                )
            )
        prev_layout = blocks[-1].type if blocks else None

    return MemoriesOut(blocks=blocks)
