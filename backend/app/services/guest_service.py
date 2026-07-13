import asyncio
from datetime import datetime, timezone
from secrets import token_urlsafe
from uuid import UUID

from sqlalchemy.ext.asyncio import AsyncSession

from app.core.errors import ConflictError, NotFoundError
from app.core.logging import logger
from app.domain.models import Event, EventStatus, Guest
from app.domain.schemas.events import EventSettingsOut
from app.domain.schemas.guests import GuestEventOut, GuestSessionOut
from app.core.config import settings
from app.infra import fcm_client, rate_limiter, s3_client
from app.repos import device_repo, event_repo, frame_repo, guest_repo, user_repo


# Anti-bruteforce for short_code guessing.
# Constant-time delay on failed lookup — timing attacks мало помогают.
_SHORT_CODE_FAIL_DELAY_SEC = 0.3
# After 30 failed short_code lookups per hour from one IP → block that IP for 1h.
_SHORT_CODE_FAIL_LIMIT = 30
_SHORT_CODE_FAIL_WINDOW = 3600


async def auto_complete_if_expired(session: AsyncSession, event: Event) -> None:
    """Self-healing: если end_at прошёл, а статус всё ещё ACTIVE — закрываем событие.
    Так же генерируем public_share_token, если его ещё нет.
    Идемпотентно, никаких side-эффектов если event уже COMPLETED/CANCELLED."""
    if event.status != EventStatus.ACTIVE:
        return
    if event.end_at is None or event.end_at > datetime.now(timezone.utc):
        return
    event.status = EventStatus.COMPLETED
    if event.public_share_token is None:
        event.public_share_token = token_urlsafe(24)
    await session.commit()
    logger.info("event_auto_completed", event_id=str(event.id), reason="end_at_passed")


async def _register_short_code_failure(client_ip: str | None) -> None:
    """Constant delay + Redis counter. Escalates to hard lockout after 30 fails/hour."""
    await asyncio.sleep(_SHORT_CODE_FAIL_DELAY_SEC)
    if not client_ip:
        return
    try:
        count = await rate_limiter.check_and_incr(
            f"guest:short_code_fail:{client_ip}",
            limit=_SHORT_CODE_FAIL_LIMIT,
            window_sec=_SHORT_CODE_FAIL_WINDOW,
        )
        if count >= _SHORT_CODE_FAIL_LIMIT * 0.8:
            logger.warning("short_code_bruteforce_suspected", client_ip=client_ip, count=count)
    except Exception:
        # rate_limiter itself raises RateLimitError above the limit — that becomes HTTP 429.
        raise


_AVATAR_URL_TTL = 86400  # 24h — как для album URLs


def _build_session_out(guest: Guest, frames_used: int, event: Event | None = None) -> GuestSessionOut:
    if event is None:
        event = guest.event
    s = event.settings
    remaining = max(0, s.frames_per_guest - frames_used)
    avatar_url = (
        s3_client.presign_get(guest.avatar_key, expires_in=_AVATAR_URL_TTL)
        if guest.avatar_key
        else None
    )
    return GuestSessionOut(
        guest_id=guest.id,
        guest_token=guest.guest_token,
        name=guest.name,
        avatar_url=avatar_url,
        bio=guest.bio,
        event=GuestEventOut(
            id=event.id,
            title=event.title,
            status=event.status.value,
            start_at=event.start_at,
            end_at=event.end_at,
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
        ),
        frames_used=frames_used,
        frames_remaining=remaining,
    )


async def join(
    session: AsyncSession,
    short_code: str,
    name: str | None,
    fingerprint: str,
    *,
    actor_user_id: UUID | None = None,
    client_ip: str | None = None,
) -> GuestSessionOut:
    """Создать или вернуть существующую гость-сессию.

    Если actor_user_id задан (Bearer токен в запросе) — гость линкуется к юзеру:
    - Проверяется существующий Guest по (user_id, event_id) — если есть, возвращаем его
    - При создании name по умолчанию = user.display_name (или явное name из payload)
    - guest.user_id = actor_user_id

    Если actor_user_id == None — анонимный flow (как раньше):
    - Поиск по (fingerprint, event_id)
    - name обязательное
    """
    event = await event_repo.get_by_short_code(session, short_code)
    if event is None:
        await _register_short_code_failure(client_ip)
        # Generic message — не помогаем брутфорсеру отличать «нет кода» от «неверный код».
        raise NotFoundError("Код не найден")

    # Self-healing: если end_at прошёл — авто-COMPLETED до статусной проверки.
    await auto_complete_if_expired(session, event)

    # Хост (event.user_id) может подключаться как «гость» в свой же альбом
    # даже в DRAFT / COMPLETED — это даёт ему встроенную камеру в приложении.
    is_owner_join = actor_user_id is not None and actor_user_id == event.user_id
    if event.status != EventStatus.ACTIVE and not is_owner_join:
        raise ConflictError(
            "Ивент ещё не начался или уже завершён",
            details={"status": event.status.value},
        )

    if not is_owner_join and event.start_at > datetime.now(timezone.utc):
        raise ConflictError(
            "Ивент ещё не начался",
            details={"start_at": event.start_at.isoformat()},
        )

    # 1. Авторизованный flow — поиск по user_id
    if actor_user_id is not None:
        existing = await guest_repo.get_by_event_and_user(session, event.id, actor_user_id)
        if existing is not None:
            # Юзер уже подключался к этому событию. Опционально обновить имя если передано.
            if name and name != existing.name:
                existing.name = name[:40]
                await session.commit()
            frames_used = await frame_repo.count_uploaded_for_guest(session, existing.id)
            return _build_session_out(existing, frames_used)

    # 2. Анонимный (или авторизованный без существующего guest) — fallback на fingerprint
    existing = await guest_repo.get_by_event_and_fingerprint(session, event.id, fingerprint)
    if existing is not None:
        # Если гость уже есть по fingerprint и сейчас пришёл с Bearer — линкуем
        if actor_user_id is not None and existing.user_id is None:
            existing.user_id = actor_user_id
            await session.commit()
        frames_used = await frame_repo.count_uploaded_for_guest(session, existing.id)
        return _build_session_out(existing, frames_used)

    # 3. Создаём нового гостя
    guests_count = await event_repo.count_guests(session, event.id)
    if guests_count >= event.settings.max_guests:
        raise ConflictError(
            "Guest limit reached",
            details={"max_guests": event.settings.max_guests},
        )

    # Определяем имя
    final_name = (name or "").strip()
    if actor_user_id is not None and not final_name:
        # Берём display_name из аккаунта
        user = await user_repo.get_by_id(session, actor_user_id)
        if user and user.display_name:
            final_name = user.display_name[:40]
    if not final_name:
        raise ConflictError("Name is required", details={"field": "name"})

    guest = Guest(
        event_id=event.id,
        user_id=actor_user_id,
        name=final_name,
        guest_token=token_urlsafe(32),
        fingerprint=fingerprint,
    )
    await guest_repo.create(session, guest)

    # Build result before commit while event/settings are still loaded in session
    result = _build_session_out(guest, frames_used=0, event=event)

    await session.commit()

    # Notify host that a new guest joined
    host_tokens = await device_repo.get_tokens_for_user(session, event.user_id)
    if host_tokens:
        guests_total = guests_count + 1
        await fcm_client.send_multicast(
            tokens=host_tokens,
            title=event.title,
            body=f"{final_name} присоединился к плёнке · {guests_total} гостей",
            data={"event_id": str(event.id), "type": "guest_joined"},
        )

    return result


async def get_session_state(session: AsyncSession, guest_token: str) -> GuestSessionOut:
    guest = await guest_repo.get_by_token(session, guest_token)
    if guest is None:
        raise NotFoundError("Guest session not found")
    # Self-healing: если end_at прошёл — закроем event тут же, чтобы клиент увидел completed.
    await auto_complete_if_expired(session, guest.event)
    frames_used = await frame_repo.count_uploaded_for_guest(session, guest.id)
    return _build_session_out(guest, frames_used)


async def update_guest_name(
    session: AsyncSession, guest_token: str, new_name: str
) -> GuestSessionOut:
    """Меняет имя для конкретного guest record (для конкретного события).
    Не трогает User.display_name — это локальная подпись."""
    guest = await guest_repo.get_by_token(session, guest_token)
    if guest is None:
        raise NotFoundError("Guest session not found")
    final_name = new_name.strip()[:40]
    if not final_name:
        raise ConflictError("Name cannot be empty", details={"field": "name"})
    guest.name = final_name
    await session.commit()
    frames_used = await frame_repo.count_uploaded_for_guest(session, guest.id)
    return _build_session_out(guest, frames_used)


def _avatar_ext_for_ct(content_type: str) -> str:
    return {
        "image/jpeg": "jpg",
        "image/jpg": "jpg",
        "image/png": "png",
        "image/webp": "webp",
    }.get(content_type.lower(), "jpg")


async def presign_avatar_upload(
    session: AsyncSession, guest_token: str, content_type: str, size_bytes: int
) -> dict:
    """Presign PUT для аватара гостя. Ключ детерминирован по guest.id — перезапись
    старого аватара новым uploadом. Клиент затем шлёт PATCH /sessions/me с avatar_key."""
    guest = await guest_repo.get_by_token(session, guest_token)
    if guest is None:
        raise NotFoundError("Guest session not found")
    if size_bytes > 2 * 1024 * 1024:
        raise ConflictError("Avatar too large", details={"max_bytes": 2 * 1024 * 1024})
    ext = _avatar_ext_for_ct(content_type)
    key = f"avatars/guests/{guest.id}.{ext}"
    upload_url = s3_client.presign_put(key, content_type)
    return {
        "avatar_key": key,
        "upload_url": upload_url,
        "expires_in": settings.S3_PRESIGN_TTL_SEC,
    }


async def update_guest_profile(
    session: AsyncSession,
    guest_token: str,
    *,
    name: str | None = None,
    avatar_key: str | None = None,
    bio: str | None = None,
) -> GuestSessionOut:
    """Обновляет любые поля профиля. None → не трогать."""
    guest = await guest_repo.get_by_token(session, guest_token)
    if guest is None:
        raise NotFoundError("Guest session not found")
    if name is not None:
        clean = name.strip()[:40]
        if not clean:
            raise ConflictError("Name cannot be empty", details={"field": "name"})
        guest.name = clean
    if avatar_key is not None:
        # Клиент должен прислать ключ, который вернул presign — простая защита от подмены.
        expected_prefix = f"avatars/guests/{guest.id}."
        if not avatar_key.startswith(expected_prefix):
            raise ConflictError("Invalid avatar key", details={"field": "avatar_key"})
        guest.avatar_key = avatar_key
    if bio is not None:
        guest.bio = bio[:160] or None
    await session.commit()
    frames_used = await frame_repo.count_uploaded_for_guest(session, guest.id)
    return _build_session_out(guest, frames_used)
