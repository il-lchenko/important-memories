from base64 import urlsafe_b64decode, urlsafe_b64encode
from datetime import datetime, timezone
from uuid import UUID

from sqlalchemy import and_, func, or_, select, tuple_
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.errors import ConflictError, NotFoundError, PermissionDeniedError
from app.domain.models import (
    Event,
    EventStatus,
    Frame,
    FrameStatus,
    Guest,
)
from app.domain.schemas.album import AlbumFrameOut, AlbumOut
from app.infra import s3_client
from app.repos import event_repo

MAX_PAGE = 100
DEFAULT_PAGE = 30


def _encode_cursor(captured_at: datetime, frame_id: UUID) -> str:
    raw = f"{captured_at.isoformat()}|{frame_id}".encode("utf-8")
    return urlsafe_b64encode(raw).decode("ascii").rstrip("=")


def _decode_cursor(cursor: str) -> tuple[datetime, UUID]:
    try:
        padding = "=" * (-len(cursor) % 4)
        raw = urlsafe_b64decode(cursor + padding).decode("utf-8")
        ts, fid = raw.split("|", 1)
        return datetime.fromisoformat(ts), UUID(fid)
    except Exception:
        raise ConflictError("Invalid cursor")


def _is_revealed_for_guests(event: Event) -> bool:
    """Whether the album is officially revealed (visible to non-owner viewers)."""
    if event.status in (EventStatus.COMPLETED, EventStatus.CANCELLED):
        return True
    # Self-healing fallback: if reveal_at passed but the worker never flipped status, still reveal.
    s = event.settings
    if s.reveal_at is not None and s.reveal_at <= datetime.now(timezone.utc):
        return True
    return False


_ALBUM_URL_TTL = 86400  # 24 h — long enough to view, share, and download without re-fetching


def _to_frame_out(frame: Frame, guest_name: str, is_mine: bool, guest_avatar_key: str | None = None) -> AlbumFrameOut:
    thumb_url = s3_client.presign_get(frame.thumbnail_url, expires_in=_ALBUM_URL_TTL) if frame.thumbnail_url else None
    preview_url = s3_client.presign_get(frame.preview_url, expires_in=_ALBUM_URL_TTL) if frame.preview_url else None
    full_url = s3_client.presign_get(frame.s3_key, expires_in=_ALBUM_URL_TTL)
    voice_url = (
        s3_client.presign_get(frame.voice_s3_key, expires_in=_ALBUM_URL_TTL)
        if frame.voice_s3_key
        else None
    )
    avatar_url = (
        s3_client.presign_get(guest_avatar_key, expires_in=_ALBUM_URL_TTL)
        if guest_avatar_key
        else None
    )
    return AlbumFrameOut(
        id=frame.id,
        guest_id=frame.guest_id,
        guest_name=guest_name,
        guest_avatar_url=avatar_url,
        captured_at=frame.captured_at,
        thumbnail_url=thumb_url,
        preview_url=preview_url,
        full_url=full_url,
        width=frame.width,
        height=frame.height,
        is_mine=is_mine,
        caption=frame.caption,
        voice_url=voice_url,
        voice_duration_ms=frame.voice_duration_ms,
        voice_peaks=frame.voice_peaks,
        rotation=frame.rotation,
    )


async def get_album(
    session: AsyncSession,
    event_id: UUID,
    *,
    actor_user_id: UUID | None = None,
    actor_guest_id: UUID | None = None,
    cursor: str | None = None,
    limit: int = DEFAULT_PAGE,
) -> AlbumOut:
    event = await event_repo.get_by_id(session, event_id)
    if event is None:
        raise NotFoundError("Event not found")

    # Определяем кто пришёл: HOST, INVITED (user_id != event.user_id, но есть Guest record), ANON
    is_owner = actor_user_id is not None and event.user_id == actor_user_id
    invited_guest_id: UUID | None = None

    if actor_user_id is not None and not is_owner:
        # Invited user: ищем Guest record для (user_id, event_id)
        from app.repos import guest_repo
        invited = await guest_repo.get_by_event_and_user(session, event_id, actor_user_id)
        if invited is None:
            raise PermissionDeniedError("Not your event")
        invited_guest_id = invited.id

    if actor_guest_id is not None:
        guest_check = await session.get(Guest, actor_guest_id)
        if guest_check is None or guest_check.event_id != event_id:
            raise PermissionDeniedError("Guest does not belong to this event")

    limit = max(1, min(limit, MAX_PAGE))
    revealed_for_guests = _is_revealed_for_guests(event)
    # Host (owner) always has access to the album — even before reveal_at — as admin preview.
    revealed = revealed_for_guests or is_owner
    is_admin_preview = is_owner and not revealed_for_guests

    total_stmt = select(func.count(Frame.id)).where(
        Frame.event_id == event_id,
        Frame.status == FrameStatus.UPLOADED,
    )
    total_frames = int((await session.execute(total_stmt)).scalar_one())

    if not revealed:
        return AlbumOut(
            items=[],
            next_cursor=None,
            revealed=False,
            total_frames=total_frames,
            is_admin_preview=False,
        )

    stmt = (
        select(Frame, Guest.name, Guest.avatar_key)
        .join(Guest, Guest.id == Frame.guest_id)
        .where(
            Frame.event_id == event_id,
            Frame.status == FrameStatus.UPLOADED,
        )
        .order_by(Frame.captured_at.desc(), Frame.id.desc())
        .limit(limit + 1)
    )

    if cursor:
        ts, fid = _decode_cursor(cursor)
        stmt = stmt.where(
            or_(
                Frame.captured_at < ts,
                and_(Frame.captured_at == ts, Frame.id < fid),
            )
        )

    rows = list((await session.execute(stmt)).all())
    has_more = len(rows) > limit
    rows = rows[:limit]

    # is_mine: для анонимного гостя — по actor_guest_id; для invited user — по invited_guest_id
    my_guest_id = actor_guest_id or invited_guest_id
    items = [
        _to_frame_out(
            frame, name,
            is_mine=(my_guest_id is not None and frame.guest_id == my_guest_id),
            guest_avatar_key=avatar_key,
        )
        for frame, name, avatar_key in rows
    ]
    next_cursor = None
    if has_more and items:
        last = rows[-1][0]
        next_cursor = _encode_cursor(last.captured_at, last.id)

    return AlbumOut(
        items=items,
        next_cursor=next_cursor,
        revealed=True,
        total_frames=total_frames,
        is_admin_preview=is_admin_preview,
    )


async def get_public_album(
    session: AsyncSession,
    public_share_token: str,
    *,
    cursor: str | None = None,
    limit: int = DEFAULT_PAGE,
) -> AlbumOut:
    """Read-only альбом по публичному share-токену. Работает только для COMPLETED/CANCELLED."""
    stmt = select(Event).where(Event.public_share_token == public_share_token)
    event = (await session.execute(stmt)).scalar_one_or_none()
    if event is None:
        raise NotFoundError("Album not found")
    if event.status not in (EventStatus.COMPLETED, EventStatus.CANCELLED):
        # Токен есть, но статус изменили — не показываем чужим.
        raise NotFoundError("Album not found")

    limit = max(1, min(limit, MAX_PAGE))
    total_stmt = select(func.count(Frame.id)).where(
        Frame.event_id == event.id,
        Frame.status == FrameStatus.UPLOADED,
    )
    total_frames = int((await session.execute(total_stmt)).scalar_one())

    frame_stmt = (
        select(Frame, Guest.name, Guest.avatar_key)
        .join(Guest, Guest.id == Frame.guest_id)
        .where(
            Frame.event_id == event.id,
            Frame.status == FrameStatus.UPLOADED,
        )
        .order_by(Frame.captured_at.desc(), Frame.id.desc())
        .limit(limit + 1)
    )
    if cursor:
        ts, fid = _decode_cursor(cursor)
        frame_stmt = frame_stmt.where(
            or_(
                Frame.captured_at < ts,
                and_(Frame.captured_at == ts, Frame.id < fid),
            )
        )

    rows = list((await session.execute(frame_stmt)).all())
    has_more = len(rows) > limit
    rows = rows[:limit]

    items = [
        _to_frame_out(frame, name, is_mine=False, guest_avatar_key=avatar_key)
        for frame, name, avatar_key in rows
    ]
    next_cursor = None
    if has_more and items:
        last = rows[-1][0]
        next_cursor = _encode_cursor(last.captured_at, last.id)

    return AlbumOut(
        items=items,
        next_cursor=next_cursor,
        revealed=True,
        total_frames=total_frames,
        is_admin_preview=False,
    )


async def get_public_meta(
    session: AsyncSession, public_share_token: str
) -> dict:
    """Meta альбома (title, cover, frame_count) для публичной ссылки."""
    stmt = select(Event).where(Event.public_share_token == public_share_token)
    event = (await session.execute(stmt)).scalar_one_or_none()
    if event is None or event.status not in (EventStatus.COMPLETED, EventStatus.CANCELLED):
        raise NotFoundError("Album not found")
    total_frames = int((await session.execute(
        select(func.count(Frame.id)).where(
            Frame.event_id == event.id,
            Frame.status == FrameStatus.UPLOADED,
        )
    )).scalar_one())
    cover_url: str | None = None
    if event.cover_url:
        # cover_url может быть либо s3_key, либо legacy URL — используем presign_get, если ключ
        key = event.cover_url
        try:
            cover_url = s3_client.presign_get(key, expires_in=_ALBUM_URL_TTL)
        except Exception:
            cover_url = event.cover_url  # legacy full URL
    return {
        "id": str(event.id),
        "title": event.title,
        "status": event.status.value,
        "cover_url": cover_url,
        "total_frames": total_frames,
        "revealed": True,
    }
