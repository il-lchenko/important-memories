from datetime import datetime, timezone
from typing import Literal
from uuid import UUID, uuid4

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.core.errors import ConflictError, NotFoundError, PermissionDeniedError, RateLimitError
from app.domain.models import EventStatus, Frame, FrameSource, FrameStatus, Guest
from app.domain.schemas.frames import (
    FramePresignOut,
    FrameRegisterOut,
    FrameUpdateIn,
    FrameVoicePresignOut,
)
from app.infra import fcm_client, queue, rate_limiter, s3_client
from app.repos import device_repo, event_repo, frame_repo


def _make_s3_key(event_id: UUID, frame_id: UUID, content_type: str) -> str:
    ext = "jpg"
    if content_type == "image/png":
        ext = "png"
    elif content_type == "image/webp":
        ext = "webp"
    elif content_type in ("image/heic", "image/heif"):
        # HEIC от iPhone — worker сконвертирует в jpg и переименует ключ.
        ext = "heic"
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
    source: Literal["camera", "upload"] = "camera",
    upload_hash: str | None = None,
) -> FramePresignOut:
    is_upload = source == "upload"
    max_bytes = 12 * 1024 * 1024 if is_upload else 20 * 1024 * 1024
    if size_bytes > max_bytes:
        raise ConflictError("File too large", details={"max_bytes": max_bytes})

    now = datetime.now(timezone.utc)
    is_owner = guest.user_id is not None and guest.user_id == guest.event.user_id
    window_ends_at = guest.event.settings.uploads_window_ends_at
    is_post_event_window_open = (
        is_upload
        and guest.event.status == EventStatus.COMPLETED
        and window_ends_at is not None
        and window_ends_at > now
    )

    if is_upload:
        # Пост-event окно от хоста: событие COMPLETED, но window > now — разрешаем.
        # Иначе — стандартные проверки (ACTIVE + uploads_enabled).
        if not is_post_event_window_open:
            if guest.event.status != EventStatus.ACTIVE:
                raise ConflictError(
                    "Загрузка доступна только во время события",
                    details={"status": guest.event.status.value},
                )
            if not guest.event.settings.uploads_enabled:
                raise ConflictError(
                    "Хост не разрешил загрузку из галереи для этого события",
                    details={"uploads_enabled": False},
                )
        # HEIC разрешён только для upload — camera-фото шлются как jpeg/png/webp.
    else:
        if guest.event.status not in (EventStatus.DRAFT, EventStatus.ACTIVE):
            raise ConflictError(
                "Съёмка завершена — альбом уже закрыт",
                details={"status": guest.event.status.value},
            )

    # end_at гейт: камере блокируем всегда, upload в пост-event окне пропускаем.
    if not is_post_event_window_open and guest.event.end_at is not None and guest.event.end_at <= now:
        raise ConflictError(
            "Съёмка завершена — время истекло",
            details={"end_at": guest.event.end_at.isoformat()},
        )

    if not is_owner and guest.event.start_at is not None and guest.event.start_at > now:
        raise ConflictError(
            "Съёмка ещё не открыта",
            details={"start_at": guest.event.start_at.isoformat()},
        )

    # Rate-limit для gallery-uploads: 1 файл / 10 сек на гостя. Защита от массового
    # заливания (5×3 фото за 3 секунды забило бы квоту и storage).
    if is_upload:
        blocked = await rate_limiter.too_soon(
            f"rl:upload:{guest.id}", cooldown_sec=10
        )
        if blocked:
            raise RateLimitError(
                "Слишком часто. Подождите 10 секунд.",
                details={"cooldown_sec": 10},
            )

    # Дедуп gallery-uploads по SHA-256: если файл уже загружен — возвращаем
    # существующий frame_id и не создаём новый. Клиент отобразит успех молча.
    if is_upload and upload_hash:
        existing = await frame_repo.find_by_upload_hash(
            session, guest.event_id, upload_hash
        )
        if existing is not None:
            upload_url = s3_client.presign_put(existing.s3_key, content_type)
            return FramePresignOut(
                frame_id=existing.id,
                upload_url=upload_url,
                expires_in=settings.S3_PRESIGN_TTL_SEC,
                deduplicated=True,
            )

    # Блокируем Guest row чтобы конкурентные presign от того же гостя
    # (двойной клик, две вкладки, дубликаты FCM) не пробили квоту кадров.
    await session.execute(
        select(Guest).where(Guest.id == guest.id).with_for_update()
    )
    used = await frame_repo.count_uploaded_for_guest(session, guest.id)
    # Считаем и PENDING (ещё не uploaded, но уже зарезервированы presign'ом).
    pending = await frame_repo.count_pending_for_guest(session, guest.id)
    limit = guest.event.settings.frames_per_guest
    if used + pending >= limit:
        raise ConflictError(
            "Frame quota exceeded",
            details={"used": used, "pending": pending, "limit": limit},
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
        source=FrameSource.UPLOAD if is_upload else FrameSource.CAMERA,
        upload_hash=upload_hash if is_upload else None,
    )
    await frame_repo.create(session, frame)
    await session.commit()

    upload_url = s3_client.presign_put(s3_key, content_type)
    return FramePresignOut(
        frame_id=frame_id,
        upload_url=upload_url,
        expires_in=settings.S3_PRESIGN_TTL_SEC,
        deduplicated=False,
    )


async def register_frame(
    session: AsyncSession,
    guest: Guest,
    frame_id: UUID,
    captured_at: datetime,
    width: int,
    height: int,
    source: Literal["camera", "upload"] = "camera",
) -> FrameRegisterOut:
    frame = await frame_repo.get_by_id(session, frame_id)
    if frame is None:
        raise NotFoundError("Frame not found")
    if frame.guest_id != guest.id:
        raise PermissionDeniedError("Not your frame")
    if frame.status != FrameStatus.PENDING:
        # Дедуп: если presign вернул существующий frame_id (уже UPLOADED),
        # клиент всё равно позвонит register — отвечаем идемпотентно.
        if frame.status == FrameStatus.UPLOADED and frame.source == FrameSource.UPLOAD:
            limit = guest.event.settings.frames_per_guest
            used = await frame_repo.count_uploaded_for_guest(session, guest.id)
            return FrameRegisterOut(
                id=frame.id,
                status=frame.status.value,
                frames_remaining=max(0, limit - used),
            )
        raise ConflictError(
            "Frame already registered",
            details={"status": frame.status.value},
        )

    frame.status = FrameStatus.UPLOADED
    frame.captured_at = captured_at
    frame.uploaded_at = datetime.now(captured_at.tzinfo)
    frame.width = width
    frame.height = height
    # source в presign уже сохранён — но register клиент может прислать явно
    # (защита от рассинхрона presign/register при retry).
    if source == "upload" and frame.source != FrameSource.UPLOAD:
        frame.source = FrameSource.UPLOAD
    # Явный flush перед подсчётом — иначе SELECT не увидит только что uploaded frame
    # и вернёт заниженный used → лишний кадр в frames_remaining.
    await session.flush()
    used = await frame_repo.count_uploaded_for_guest(session, guest.id)
    guest.frames_used = used
    await session.commit()

    # Для gallery-uploads worker обязан применить LUT + snapping EXIF (безопасность).
    # Для camera-фото фильтр уже применён клиентом — worker только делает thumb/preview.
    force_lut = frame.source == FrameSource.UPLOAD
    await queue.make_thumbnail(frame.id, force_lut=force_lut)

    # Пуш хосту. Чтобы не спамить — только на первый кадр от гостя.
    # И не отправляем если хост сам себе снимает (guest.user_id == event.user_id).
    host_id = guest.event.user_id
    is_owner_shot = guest.user_id is not None and guest.user_id == host_id
    if used == 1 and not is_owner_shot:
        host_tokens = await device_repo.get_tokens_for_user(session, host_id)
        if host_tokens:
            await fcm_client.send_multicast(
                tokens=host_tokens,
                title=guest.event.title,
                body=f"{guest.name} снял первый кадр",
                data={
                    "event_id": str(guest.event_id),
                    "type": "new_frame",
                },
            )

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

    if payload.clear_note:
        frame.note = None
    elif payload.note is not None:
        frame.note = payload.note.strip() or None

    if payload.rotation is not None:
        frame.rotation = payload.rotation

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
