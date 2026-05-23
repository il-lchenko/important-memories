from base64 import urlsafe_b64decode, urlsafe_b64encode
from datetime import datetime
from uuid import UUID

from sqlalchemy import and_, func, or_, select, tuple_
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.errors import NotFoundError, PermissionDeniedError
from app.domain.models import (
    Event,
    EventStatus,
    Frame,
    FrameStatus,
    Guest,
    RevealMode,
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
    padding = "=" * (-len(cursor) % 4)
    raw = urlsafe_b64decode(cursor + padding).decode("utf-8")
    ts, fid = raw.split("|", 1)
    return datetime.fromisoformat(ts), UUID(fid)


def _is_revealed(event: Event) -> bool:
    s = event.settings
    if s.reveal_mode == RevealMode.INSTANT:
        return True
    return event.status in (EventStatus.COMPLETED, EventStatus.CANCELLED)


def _to_frame_out(frame: Frame, guest_name: str, is_mine: bool) -> AlbumFrameOut:
    thumb_url = s3_client.presign_get(frame.thumbnail_url) if frame.thumbnail_url else None
    full_url = s3_client.presign_get(frame.s3_key)
    return AlbumFrameOut(
        id=frame.id,
        guest_id=frame.guest_id,
        guest_name=guest_name,
        captured_at=frame.captured_at,
        thumbnail_url=thumb_url,
        full_url=full_url,
        width=frame.width,
        height=frame.height,
        is_mine=is_mine,
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

    if actor_user_id is not None and event.user_id != actor_user_id:
        raise PermissionDeniedError("Not your event")
    if actor_guest_id is not None:
        guest_check = await session.get(Guest, actor_guest_id)
        if guest_check is None or guest_check.event_id != event_id:
            raise PermissionDeniedError("Guest does not belong to this event")

    limit = max(1, min(limit, MAX_PAGE))
    is_owner = actor_user_id is not None and event.user_id == actor_user_id
    revealed = _is_revealed(event) or is_owner

    total_stmt = select(func.count(Frame.id)).where(
        Frame.event_id == event_id,
        Frame.status == FrameStatus.UPLOADED,
    )
    total_frames = int((await session.execute(total_stmt)).scalar_one())

    if not revealed:
        return AlbumOut(items=[], next_cursor=None, revealed=False, total_frames=total_frames)

    stmt = (
        select(Frame, Guest.name)
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

    items = [
        _to_frame_out(frame, name, is_mine=(actor_guest_id is not None and frame.guest_id == actor_guest_id))
        for frame, name in rows
    ]
    next_cursor = None
    if has_more and items:
        last = rows[-1][0]
        next_cursor = _encode_cursor(last.captured_at, last.id)

    return AlbumOut(items=items, next_cursor=next_cursor, revealed=True, total_frames=total_frames)
