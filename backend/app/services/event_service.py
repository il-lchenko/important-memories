from datetime import datetime, timedelta, timezone
from io import BytesIO
from uuid import UUID

import qrcode
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.core.errors import ConflictError, NotFoundError, PermissionDeniedError
from app.core.short_code import generate as generate_short_code
from app.domain.models import (
    Event,
    EventSettings,
    EventStatus,
    LutPreset,
    PhotoFormat,
    Plan,
    RevealMode,
)
from app.domain.schemas.events import (
    EventCreateIn,
    EventOut,
    EventSettingsOut,
    EventSettingsUpdateIn,
    EventUpdateIn,
)
from app.infra import fcm_client, queue, rate_limiter, s3_client
from app.repos import device_repo, event_repo

# Business plan v3.2 — pricing grid by guest count (analysis/business-plan/index.html §09).
# Kept in one place so pricing/limits/retention stay in sync.

_PLAN_LIMITS: dict[Plan, int] = {
    Plan.FREE: 5,
    Plan.P10: 10,
    Plan.P25: 25,
    Plan.P50: 50,
    Plan.P75: 75,
    Plan.P100: 100,
    Plan.P150: 150,
    Plan.P175: 175,
    Plan.P200: 200,
    Plan.P250: 250,
    Plan.CUSTOM: 10_000,     # для 250+ (реальный лимит в EventSettings.max_guests)
    Plan.UNLIMITED: 10_000,  # legacy
}

# Price in kopecks (для YooKassa) — ровно как в бизнес-плане.
_PLAN_PRICE_KOPECKS: dict[Plan, int] = {
    Plan.FREE: 0,
    Plan.P10: 24900,
    Plan.P25: 44900,
    Plan.P50: 129000,
    Plan.P75: 199000,
    Plan.P100: 299000,
    Plan.P150: 449000,
    Plan.P175: 549000,
    Plan.P200: 629000,
    Plan.P250: 769000,
    # CUSTOM: рассчитывается формулой price_for_guests()
}

# Default storage retention (days) per plan.
_PLAN_RETENTION_DAYS: dict[Plan, int] = {
    Plan.FREE: 14,
    Plan.P10: 30,
    Plan.P25: 60,
    Plan.P50: 90,
    Plan.P75: 90,
    Plan.P100: 120,
    Plan.P150: 150,
    Plan.P175: 180,
    Plan.P200: 180,
    Plan.P250: 240,
    Plan.CUSTOM: 240,
    Plan.UNLIMITED: 240,
}


def price_for_guests(guests: int) -> int:
    """Return price in kopecks for arbitrary guest count.

    - Discrete tiers up to 250 map to _PLAN_PRICE_KOPECKS.
    - 250 < N ≤ 2000: formula 7690 + (N-250)*30 ₽ (plateau 30₽/guest).
    - N > 2000: not returned here (needs B2B contact).
    """
    if guests <= 5:
        return 0
    if guests <= 10:  return _PLAN_PRICE_KOPECKS[Plan.P10]
    if guests <= 25:  return _PLAN_PRICE_KOPECKS[Plan.P25]
    if guests <= 50:  return _PLAN_PRICE_KOPECKS[Plan.P50]
    if guests <= 75:  return _PLAN_PRICE_KOPECKS[Plan.P75]
    if guests <= 100: return _PLAN_PRICE_KOPECKS[Plan.P100]
    if guests <= 150: return _PLAN_PRICE_KOPECKS[Plan.P150]
    if guests <= 175: return _PLAN_PRICE_KOPECKS[Plan.P175]
    if guests <= 200: return _PLAN_PRICE_KOPECKS[Plan.P200]
    if guests <= 250: return _PLAN_PRICE_KOPECKS[Plan.P250]
    if guests <= 2000:
        rubles = 7690 + (guests - 250) * 30
        return rubles * 100
    return -1  # sentinel: needs B2B


# Extra frames: base 30, extended to 45 for +5₽/guest.
FRAMES_BASE_PER_GUEST = 30
FRAMES_EXTENDED_PER_GUEST = 45
FRAMES_EXTENSION_PRICE_KOPECKS_PER_GUEST = 500  # +5₽

# Storage extensions after event completion.
STORAGE_EXTENSIONS: dict[str, tuple[int, int]] = {
    # key: (days, price_kopecks)
    "3m": (90, 49000),
    "6m": (180, 79000),
    "1y": (365, 129000),
}


def default_expires_at(plan: Plan, activated_at: datetime | None = None) -> datetime:
    """Compute expires_at for an event newly activated on `plan`."""
    base = activated_at or datetime.now(timezone.utc)
    return base + timedelta(days=_PLAN_RETENTION_DAYS.get(plan, 60))


async def _allocate_short_code(session: AsyncSession) -> str:
    for _ in range(8):
        code = generate_short_code(8)
        if not await event_repo.short_code_exists(session, code):
            return code
    raise ConflictError("Failed to allocate unique short_code")


async def _load_owned(session: AsyncSession, event_id: UUID, user_id: UUID) -> Event:
    event = await event_repo.get_by_id(session, event_id)
    if event is None:
        raise NotFoundError("Event not found")
    if event.user_id != user_id:
        raise PermissionDeniedError("Not your event")
    return event


def _resolve_cover_url(stored: str | None) -> str | None:
    """cover_url хранится либо как S3-ключ (новый формат), либо как готовый
    presigned URL (легаси). В обоих случаях возвращаем свежий короткоживущий
    presigned URL, чтобы клиенты не упирались в просроченный legacy-линк."""
    if not stored:
        return None
    if stored.startswith("http"):
        # Legacy: '<host>/<bucket>/<key>?...'. Вытаскиваем ключ.
        bare = stored.split("?", 1)[0]
        marker = f"/{settings.S3_BUCKET}/"
        idx = bare.find(marker)
        if idx == -1:
            return stored
        key = bare[idx + len(marker):]
    else:
        key = stored
    return s3_client.presign_get(key, expires_in=86400)


def _to_out(event: Event, guests_count: int = 0, frames_count: int = 0) -> EventOut:
    s = event.settings
    return EventOut(
        id=event.id,
        short_code=event.short_code,
        title=event.title,
        start_at=event.start_at,
        end_at=event.end_at,
        expires_at=event.expires_at,
        event_type=event.event_type,
        status=event.status,
        cover_url=_resolve_cover_url(event.cover_url),
        created_at=event.created_at,
        updated_at=event.updated_at,
        settings=EventSettingsOut(
            frames_per_guest=s.frames_per_guest,
            max_guests=s.max_guests,
            reveal_mode=s.reveal_mode,
            reveal_at=s.reveal_at,
            plan=s.plan,
            lut_preset=s.lut_preset,
            sound_enabled=s.sound_enabled,
            photo_format=s.photo_format,
        ),
        guests_count=guests_count,
        frames_count=frames_count,
    )


async def create_event(
    session: AsyncSession, user_id: UUID, payload: EventCreateIn
) -> EventOut:
    await rate_limiter.check_and_incr(
        f"events:create:user:{user_id}", limit=5, window_sec=3600
    )
    short_code = await _allocate_short_code(session)
    # expires_at рассчитываем сразу с учётом купленного продления хранения (checkout).
    extra_days = 0
    if payload.storage_extension is not None:
        ext = STORAGE_EXTENSIONS.get(payload.storage_extension)
        if ext is not None:
            extra_days = ext[0]
    base_days = _PLAN_RETENTION_DAYS.get(payload.plan, 60)
    expires_at = datetime.now(timezone.utc) + timedelta(days=base_days + extra_days)

    event = Event(
        user_id=user_id,
        short_code=short_code,
        title=payload.title,
        start_at=payload.start_at,
        end_at=payload.end_at,
        expires_at=expires_at,
        event_type=payload.event_type,
        status=EventStatus.DRAFT,
    )
    event.settings = EventSettings(
        max_guests=_PLAN_LIMITS[payload.plan],
        frames_per_guest=payload.frames_per_guest,
        reveal_mode=payload.reveal_mode,
        reveal_at=payload.reveal_at,
        lut_preset=payload.lut_preset or LutPreset.PORTRA400,
        plan=payload.plan,
        photo_format=payload.photo_format,
    )
    await event_repo.create(session, event)
    await session.commit()
    return _to_out(event)


async def list_events(session: AsyncSession, user_id: UUID) -> list[EventOut]:
    from sqlalchemy import func, select
    from app.domain.models import Frame, Guest

    events = await event_repo.list_for_user(session, user_id)
    if not events:
        return []
    event_ids = [e.id for e in events]
    g_rows = await session.execute(
        select(Guest.event_id, func.count(Guest.id))
        .where(Guest.event_id.in_(event_ids))
        .group_by(Guest.event_id)
    )
    f_rows = await session.execute(
        select(Frame.event_id, func.count(Frame.id))
        .where(Frame.event_id.in_(event_ids))
        .group_by(Frame.event_id)
    )
    guests_map = {r[0]: r[1] for r in g_rows}
    frames_map = {r[0]: r[1] for r in f_rows}
    return [_to_out(e, guests_map.get(e.id, 0), frames_map.get(e.id, 0)) for e in events]


async def get_event(session: AsyncSession, user_id: UUID, event_id: UUID) -> EventOut:
    from sqlalchemy import func, select
    from app.domain.models import Frame, Guest

    event = await _load_owned(session, event_id, user_id)
    g = (await session.execute(
        select(func.count(Guest.id)).where(Guest.event_id == event_id)
    )).scalar_one()
    f = (await session.execute(
        select(func.count(Frame.id)).where(Frame.event_id == event_id)
    )).scalar_one()
    return _to_out(event, int(g), int(f))


async def update_settings(
    session: AsyncSession,
    user_id: UUID,
    event_id: UUID,
    payload: EventSettingsUpdateIn,
) -> EventOut:
    event = await _load_owned(session, event_id, user_id)
    guests_count = await event_repo.count_guests(session, event_id)
    if guests_count > 0 and any([
        payload.frames_per_guest is not None,
        payload.plan is not None,
        payload.lut_preset is not None,
        payload.sound_enabled is not None,
        payload.photo_format is not None,
    ]):
        raise ConflictError(
            "Settings locked after first guest joined",
            details={"guests_joined": guests_count},
        )

    s = event.settings
    if payload.frames_per_guest is not None:
        s.frames_per_guest = payload.frames_per_guest
    if payload.reveal_mode is not None:
        s.reveal_mode = payload.reveal_mode
    if payload.reveal_at is not None:
        s.reveal_at = payload.reveal_at
    if payload.plan is not None:
        s.plan = payload.plan
        s.max_guests = _PLAN_LIMITS[payload.plan]
    if payload.lut_preset is not None:
        s.lut_preset = payload.lut_preset
    if payload.sound_enabled is not None:
        s.sound_enabled = payload.sound_enabled
    if payload.photo_format is not None:
        s.photo_format = payload.photo_format

    if s.reveal_mode == RevealMode.DELAYED:
        if s.reveal_at is None:
            raise ConflictError("reveal_at is required for delayed reveal")
        if s.reveal_at <= datetime.now(timezone.utc):
            raise ConflictError("reveal_at must be in the future")

    await session.commit()
    if (
        s.reveal_mode == RevealMode.DELAYED
        and s.reveal_at is not None
        and event.status == EventStatus.ACTIVE
    ):
        await queue.schedule_reveal(event.id, s.reveal_at)
    return _to_out(event)


async def activate_event(
    session: AsyncSession, user_id: UUID, event_id: UUID
) -> EventOut:
    """DEV-only stub. In prod, activation happens via /webhooks/yookassa after payment."""
    event = await _load_owned(session, event_id, user_id)
    if event.status != EventStatus.DRAFT:
        raise ConflictError(
            "Only draft events can be activated",
            details={"status": event.status.value},
        )
    event.status = EventStatus.ACTIVE
    # Set storage expiration if not already set (e.g. on manual DEV activate).
    if event.expires_at is None:
        event.expires_at = default_expires_at(event.settings.plan)
    await session.commit()
    return _to_out(event)


async def complete_event(
    session: AsyncSession, user_id: UUID, event_id: UUID
) -> EventOut:
    event = await _load_owned(session, event_id, user_id)
    if event.status != EventStatus.ACTIVE:
        raise ConflictError(
            "Only active events can be completed",
            details={"status": event.status.value},
        )
    event.status = EventStatus.COMPLETED
    await session.commit()
    return _to_out(event)


async def reveal_event(
    session: AsyncSession, user_id: UUID, event_id: UUID
) -> EventOut:
    """Manual immediate reveal — same effect as completing the event."""
    event = await _load_owned(session, event_id, user_id)
    if event.status != EventStatus.ACTIVE:
        raise ConflictError(
            "Only active events can be revealed",
            details={"status": event.status.value},
        )
    event.status = EventStatus.COMPLETED
    await session.commit()

    # Notify host (fire-and-forget: don't block the response)
    host_tokens = await device_repo.get_tokens_for_user(session, user_id)
    if host_tokens:
        await fcm_client.send_multicast(
            tokens=host_tokens,
            title=event.title,
            body="Альбом открыт — гости уже могут его смотреть!",
            data={"event_id": str(event_id), "type": "album_revealed"},
        )

    return _to_out(event)


def build_qr_png(short_code: str) -> tuple[str, bytes]:
    short_url = f"{settings.PUBLIC_PWA_BASE_URL.rstrip('/')}/g/{short_code}"
    img = qrcode.make(short_url)
    buf = BytesIO()
    img.save(buf, format="PNG")
    return short_url, buf.getvalue()


async def rename_event(
    session: AsyncSession, user_id: UUID, event_id: UUID, title: str
) -> EventOut:
    event = await _load_owned(session, event_id, user_id)
    event.title = title
    await session.commit()
    return _to_out(event)


async def update_event(
    session: AsyncSession,
    user_id: UUID,
    event_id: UUID,
    payload: EventUpdateIn,
) -> EventOut:
    event = await _load_owned(session, event_id, user_id)
    if payload.title is not None:
        event.title = payload.title
    if payload.event_type is not None:
        event.event_type = payload.event_type
    if payload.start_at is not None:
        if event.status != EventStatus.DRAFT:
            raise ConflictError(
                "Нельзя изменить время начала активного события",
                details={"status": event.status.value},
            )
        event.start_at = payload.start_at
    await session.commit()
    return _to_out(event)


async def cancel_event(
    session: AsyncSession, user_id: UUID, event_id: UUID
) -> None:
    event = await _load_owned(session, event_id, user_id)
    if event.status == EventStatus.ACTIVE:
        raise ConflictError(
            "Нельзя удалить активное событие",
            details={"status": event.status.value},
        )
    event.status = EventStatus.CANCELLED
    await session.commit()


async def generate_qr(
    session: AsyncSession, user_id: UUID, event_id: UUID
) -> tuple[str, bytes]:
    event = await _load_owned(session, event_id, user_id)
    return build_qr_png(event.short_code)


async def upload_cover(
    session: AsyncSession,
    user_id: UUID,
    event_id: UUID,
    data: bytes,
    content_type: str,
) -> EventOut:
    if content_type not in {"image/jpeg", "image/png", "image/webp"}:
        raise ConflictError("Unsupported image type; use JPEG, PNG, or WebP")
    if len(data) > 10 * 1024 * 1024:
        raise ConflictError("Cover image too large", details={"max_bytes": 10 * 1024 * 1024})

    ext = {"image/png": "png", "image/webp": "webp"}.get(content_type, "jpg")
    key = f"events/{event_id}/cover.{ext}"
    s3_client.upload_bytes(key, data, content_type)

    # Храним только S3-ключ — клиенту отдадим свежий presign в _to_out.
    event = await _load_owned(session, event_id, user_id)
    event.cover_url = key
    await session.commit()
    return _to_out(event)
