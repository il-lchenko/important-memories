from datetime import datetime, timezone
from uuid import UUID, uuid4

from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.core.errors import ConflictError, NotFoundError, PermissionDeniedError
from app.domain.models import EventStatus, Frame, FrameStatus, Guest
from app.domain.schemas.frames import (
    FramePresignOut,
    FrameRegisterOut,
    FrameUpdateIn,
    FrameVoicePresignOut,
)
from app.infra import queue, s3_client
from app.repos import event_repo, frame_repo


def _make_s3_key(event_id: UUID, frame_id: UUID, content_type: str) -> str:
    ext = "jpg"
    if content_type == "image/png":
        ext = "png"
    elif content_type == "image/webp":
        ext = "webp"
    return f"events/{event_id}/frames/{frame_id}.{ext}"


def _make_voice_s3_key(event_id: UUID, frame_id: UUID, content_type: str) -> str:
    ext = "webm"
    if content_type == "audio/ogg":
        ext = "ogg"
    elif content_type == "audio/mp4":
        ext = "m4a"
    elif content_type in ("audio/wav", "audio/wave"):
        ext = "wav"
    elif content_type == "audio/mpeg":
        ext = "mp3"
    return f"events/{event_id}/voices/{frame_id}.{ext}"


async def presign_upload(
    session: AsyncSession,
    guest: Guest,
    content_type: str,
    size_bytes: int,
) -> FramePresignOut:
    if size_bytes > 20 * 1024 * 1024:
        raise ConflictError("File too large", details={"max_bytes": 20 * 1024 * 1024})

    if guest.event.status not in (EventStatus.DRAFT, EventStatus.ACTIVE):
        raise ConflictError(
            "Съёмка завершена — альбом уже закрыт",
            details={"status": guest.event.status.value},
        )

    used = await frame_repo.count_non_deleted_for_guest(session, guest.id)
    limit = guest.event.settings.frames_per_guest
    if used >= limit:
        raise ConflictError(
            "Frame quota exceeded",
            details={"used": used, "limit": limit},
        )

    frame_id = uuid4()
    s3_key = _make_s3_key(guest.event_id, frame_id, content_type)
    frame = Frame(
        id=frame_id,
        event_id=guest.event_id,
        guest_id=guest.id,
        s3_key=s3_key,
        size_bytes=size_bytes,
        status=FrameStatus.PENDING,
    )
    await frame_repo.create(session, frame)
    await session.commit()

    upload_url = s3_client.presign_put(s3_key, content_type)
    return FramePresignOut(
        frame_id=frame_id,
        upload_url=upload_url,
        expires_in=settings.S3_PRESIGN_TTL_SEC,
    )


async def register_frame(
    session: AsyncSession,
    guest: Guest,
    frame_id: UUID,
    captured_at: datetime,
    width: int,
    height: int,
) -> FrameRegisterOut:
    frame = await frame_repo.get_by_id(session, frame_id)
    if frame is None:
        raise NotFoundError("Frame not found")
    if frame.guest_id != guest.id:
        raise PermissionDeniedError("Not your frame")
    if frame.status != FrameStatus.PENDING:
        raise ConflictError(
            "Frame already registered",
            details={"status": frame.status.value},
        )

    frame.status = FrameStatus.UPLOADED
    frame.captured_at = captured_at
    frame.uploaded_at = datetime.now(captured_at.tzinfo)
    frame.width = width
    frame.height = height
    used = await frame_repo.count_non_deleted_for_guest(session, guest.id)
    guest.frames_used = used
    await session.commit()

    await queue.make_thumbnail(frame.id)

    limit = guest.event.settings.frames_per_guest
    return FrameRegisterOut(
        id=frame.id,
        status=frame.status.value,
        frames_remaining=max(0, limit - used),
    )


async def presign_voice(
    session: AsyncSession,
    guest: Guest,
    frame_id: UUID,
    content_type: str,
    size_bytes: int,
) -> FrameVoicePresignOut:
    if size_bytes > 2 * 1024 * 1024:
        raise ConflictError("Voice file too large", details={"max_bytes": 2 * 1024 * 1024})

    frame = await frame_repo.get_by_id(session, frame_id)
    if frame is None or frame.status == FrameStatus.DELETED:
        raise NotFoundError("Frame not found")
    if frame.guest_id != guest.id:
        raise PermissionDeniedError("Not your frame")

    s3_key = _make_voice_s3_key(frame.event_id, frame.id, content_type)
    upload_url = s3_client.presign_put(s3_key, content_type)
    return FrameVoicePresignOut(
        voice_s3_key=s3_key,
        upload_url=upload_url,
        expires_in=settings.S3_PRESIGN_TTL_SEC,
    )


async def update_frame(
    session: AsyncSession,
    guest: Guest,
    frame_id: UUID,
    payload: FrameUpdateIn,
) -> Frame:
    frame = await frame_repo.get_by_id(session, frame_id)
    if frame is None or frame.status == FrameStatus.DELETED:
        raise NotFoundError("Frame not found")
    if frame.guest_id != guest.id:
        raise PermissionDeniedError("Not your frame")

    # Caption and voice are mutually exclusive — setting one clears the other.
    if payload.clear_caption:
        frame.caption = None
    elif payload.caption is not None:
        frame.caption = payload.caption.strip() or None
        if frame.caption:
            frame.voice_s3_key = None
            frame.voice_duration_ms = None
            frame.voice_peaks = None

    if payload.clear_voice:
        frame.voice_s3_key = None
        frame.voice_duration_ms = None
        frame.voice_peaks = None
    elif payload.voice_s3_key is not None:
        frame.voice_s3_key = payload.voice_s3_key
        frame.voice_duration_ms = payload.voice_duration_ms
        frame.voice_peaks = payload.voice_peaks
        if frame.voice_s3_key:
            frame.caption = None

    await session.commit()
    return frame


async def update_rotation(
    session: AsyncSession,
    actor_user_id: UUID,
    event_id: UUID,
    frame_id: UUID,
    rotation: int,
) -> Frame:
    frame = await frame_repo.get_by_id(session, frame_id)
    if frame is None or frame.status == FrameStatus.DELETED:
        raise NotFoundError("Frame not found")
    if frame.event_id != event_id:
        raise NotFoundError("Frame not found in this event")

    event = await event_repo.get_by_id(session, event_id)
    if event is None or event.user_id != actor_user_id:
        raise PermissionDeniedError("Not your event")

    frame.rotation = rotation
    await session.commit()
    return frame


async def delete_frame(
    session: AsyncSession,
    frame_id: UUID,
    *,
    actor_user_id: UUID | None = None,
    actor_guest_id: UUID | None = None,
) -> None:
    frame = await frame_repo.get_by_id(session, frame_id)
    if frame is None or frame.status == FrameStatus.DELETED:
        raise NotFoundError("Frame not found")

    if actor_user_id is not None:
        event = await event_repo.get_by_id(session, frame.event_id)
        if event is None or event.user_id != actor_user_id:
            raise PermissionDeniedError("Not your event")
    elif actor_guest_id is not None:
        if frame.guest_id != actor_guest_id:
            raise PermissionDeniedError("Not your frame")
    else:
        raise PermissionDeniedError("No actor identified")

    frame.status = FrameStatus.DELETED
    frame.deleted_at = datetime.now(timezone.utc)
    await session.commit()
