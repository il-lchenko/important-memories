import asyncio
from datetime import datetime, timezone
from secrets import token_urlsafe
from uuid import UUID

from sqlalchemy.ext.asyncio import AsyncSession

from app.core.client_ctx import hash_fingerprint, hash_ip
from app.core.errors import (
    AlbumCapError,
    BadPinError,
    ConflictError,
    NotFoundError,
    PinRequiredError,
    RateLimitError,
)
from app.core.logging import logger
from app.domain.models import Event, EventStatus, Guest, JoinAttemptOutcome
from app.domain.schemas.events import EventSettingsOut
from app.domain.schemas.guests import GuestEventOut, GuestSessionOut
from app.core.config import settings
from app.infra import fcm_client, rate_limiter, s3_client
from app.repos import (
    device_repo,
    event_repo,
    frame_repo,
    guest_repo,
    join_attempt_repo,
    user_repo,
)


# Anti-bruteforce для угадывания short_code / PIN.
# Константный delay на любой outcome — не сигналим таймингом «код существует».
_JOIN_DELAY_SEC = 0.3

# Rate-limit на IP:
# - bad_code (промах по коду): 10/час — ужёсточили с 30
# - session-create (любая попытка POST /sessions): 10/час
_BAD_CODE_LIMIT_PER_IP = 10
_BAD_CODE_WINDOW_SEC = 3600
_SESSION_LIMIT_PER_IP = 10
_SESSION_WINDOW_SEC = 3600

# Rate-limit на fingerprint:
# - bad_code промахи: 5/час
# - bad_pin промахи: 5/час
# - новые события (успешный join новых альбомов): 3/сутки
_BAD_CODE_LIMIT_PER_FP = 5
_BAD_PIN_LIMIT_PER_FP = 5
_ALBUM_CAP_PER_FP = 3
_ALBUM_CAP_WINDOW_SEC = 86400  # 24h

# Suspicious-push хосту: если за последний час на событие пришло ≥20 неудачных
# попыток (bad_code + bad_pin), шлём push (не чаще 1 раза в час на event).
_SUSPICIOUS_THRESHOLD_1H = 20
_SUSPICIOUS_COOLDOWN_SEC = 3600


async def auto_complete_if_expired(session: AsyncSession, event: Event) -> None:
    """Self-healing: если end_at прошёл, а статус всё ещё ACTIVE — закрываем событие.
    public_share_token НЕ создаётся автоматически — это отдельное явное действие
    Хоста через POST /events/{id}/public-share/enable.
    Идемпотентно, никаких side-эффектов если event уже COMPLETED/CANCELLED."""
    if event.status != EventStatus.ACTIVE:
        return
    if event.end_at is None or event.end_at > datetime.now(timezone.utc):
        return
    event.status = EventStatus.COMPLETED
    await session.commit()
    logger.info("event_auto_completed", event_id=str(event.id), reason="end_at_passed")


async def _delay() -> None:
    """Константный delay на любой outcome — убирает timing-oracle
    «код существует vs. не существует»."""
    await asyncio.sleep(_JOIN_DELAY_SEC)


async def _check_session_rate(client_ip: str | None) -> None:
    """Общий rate-limit на POST /sessions по IP. Останавливает флуд до входа
    в основную логику. Раньше этой защиты не было — можно было спамить POST
    сколько угодно после того, как найдёшь валидный код."""
    if not client_ip:
        return
    await rate_limiter.check_and_incr(
        f"guest:sessions_ip:{client_ip}",
        limit=_SESSION_LIMIT_PER_IP,
        window_sec=_SESSION_WINDOW_SEC,
    )


async def _register_bad_code(client_ip: str | None, fp_hash: str | None) -> None:
    """Промах по short_code. Инкрементим IP и fp счётчики; каждый выше своего
    предела → 429."""
    if client_ip:
        count = await rate_limiter.check_and_incr(
            f"guest:bad_code_ip:{client_ip}",
            limit=_BAD_CODE_LIMIT_PER_IP,
            window_sec=_BAD_CODE_WINDOW_SEC,
        )
        if count >= _BAD_CODE_LIMIT_PER_IP * 0.8:
            logger.warning("bad_code_ip_high", ip=client_ip, count=count)
    if fp_hash:
        await rate_limiter.check_and_incr(
            f"guest:bad_code_fp:{fp_hash}",
            limit=_BAD_CODE_LIMIT_PER_FP,
            window_sec=_BAD_CODE_WINDOW_SEC,
        )


async def _register_bad_pin(fp_hash: str | None) -> None:
    """Промах по PIN. Считаем только по fingerprint — если хост включил PIN,
    гости с одного устройства не должны подобрать чужой PIN. IP не трогаем,
    чтобы не рушить лимит одного WiFi (в кафе много клиентов за одним IP)."""
    if fp_hash:
        await rate_limiter.check_and_incr(
            f"guest:bad_pin_fp:{fp_hash}",
            limit=_BAD_PIN_LIMIT_PER_FP,
            window_sec=_BAD_CODE_WINDOW_SEC,
        )


async def _maybe_notify_suspicious(
    session: AsyncSession, event: Event
) -> None:
    """Проверить всплеск неудачных попыток и, если пороговый — уведомить хоста.
    Cooldown 1ч через Redis SETNX — не спамим повторно.
    Не бросаем ничего наверх: аудит-нотификация не должна ронять guest-flow."""
    try:
        agg = await join_attempt_repo.stats_for_event(session, event.id, hours=1)
        per = agg.get("per_outcome", {})
        bad = int(per.get(JoinAttemptOutcome.BAD_CODE.value, 0)) + int(
            per.get(JoinAttemptOutcome.BAD_PIN.value, 0)
        )
        if bad < _SUSPICIOUS_THRESHOLD_1H:
            return
        # Anti-spam: не чаще 1 раза в час.
        already_sent = await rate_limiter.too_soon(
            f"guest:suspicious_notified:{event.id}",
            cooldown_sec=_SUSPICIOUS_COOLDOWN_SEC,
        )
        if already_sent:
            return
        host_tokens = await device_repo.get_tokens_for_user(session, event.user_id)
        if not host_tokens:
            return
        await fcm_client.send_multicast(
            tokens=host_tokens,
            title="⚠ Подозрительная активность",
            body=f"«{event.title}»: {bad} неудачных попыток входа за час",
            data={"event_id": str(event.id), "type": "suspicious_activity"},
        )
        logger.warning(
            "suspicious_notified",
            event_id=str(event.id),
            bad_count=bad,
        )
    except Exception as e:
        logger.warning("suspicious_notify_failed", error=str(e))


async def _check_album_cap(
    session: AsyncSession, fp_hash: str | None, event_id: UUID
) -> None:
    """Не даём одному fingerprint присоединять >N новых альбомов за 24ч.
    Re-join уже знакомого альбома (был успешный ok в окне) — не считается."""
    if not fp_hash:
        return
    # 1) Проверка «это re-join знакомого альбома?»
    already = await join_attempt_repo.has_ok_for_event_and_fingerprint(
        session, event_id, fp_hash, hours=_ALBUM_CAP_WINDOW_SEC // 3600
    )
    if already:
        return
    # 2) Иначе смотрим сколько distinct событий уже присоединил за окно.
    count = await join_attempt_repo.count_new_events_for_fingerprint(
        session, fp_hash, hours=_ALBUM_CAP_WINDOW_SEC // 3600
    )
    if count >= _ALBUM_CAP_PER_FP:
        raise AlbumCapError(
            "Слишком много новых альбомов за сутки",
            details={"max_per_day": _ALBUM_CAP_PER_FP, "window_hours": 24},
        )


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
    pin: str | None = None,
    invite_bypass: bool = False,
) -> GuestSessionOut:
    """Создать или вернуть существующую гость-сессию.

    Anti-brute защита (все — константный delay + запись в join_attempts):
    - short_code промах → 429 если >10/час на IP или >5/час на fingerprint
    - PIN промах → 429 если >5/час на fingerprint
    - Cap «3 новых альбома / 24ч» на fingerprint (re-join не считается)
    - `invite_bypass=True` (пришёл по /guest/invites/<token>) — обходит PIN и cap

    Если actor_user_id задан — гость линкуется к юзеру (get_by_event_and_user).
    Иначе анонимный (get_by_event_and_fingerprint).
    """
    fp_hash = hash_fingerprint(fingerprint)
    ip_hash_ = hash_ip(client_ip)

    # 0. Rate-limit на POST /sessions по IP — до любой работы.
    try:
        await _check_session_rate(client_ip)
    except RateLimitError:
        await join_attempt_repo.record(
            session, event_id=None, ip_hash=ip_hash_, fingerprint_hash=fp_hash,
            short_code_tried=short_code, pin_tried=bool(pin),
            outcome=JoinAttemptOutcome.RATE_LIMITED,
        )
        await _delay()
        raise

    event = await event_repo.get_by_short_code(session, short_code)
    if event is None:
        try:
            await _register_bad_code(client_ip, fp_hash)
        except RateLimitError:
            await join_attempt_repo.record(
                session, event_id=None, ip_hash=ip_hash_, fingerprint_hash=fp_hash,
                short_code_tried=short_code, pin_tried=bool(pin),
                outcome=JoinAttemptOutcome.RATE_LIMITED,
            )
            await _delay()
            raise
        await join_attempt_repo.record(
            session, event_id=None, ip_hash=ip_hash_, fingerprint_hash=fp_hash,
            short_code_tried=short_code, pin_tried=bool(pin),
            outcome=JoinAttemptOutcome.BAD_CODE,
        )
        await _delay()
        # Generic message — не помогаем брутфорсеру отличать «нет кода» от «неверный код».
        raise NotFoundError("Код не найден")

    # Self-healing: если end_at прошёл — авто-COMPLETED до статусной проверки.
    await auto_complete_if_expired(session, event)

    # Хост (event.user_id) может подключаться как «гость» в свой же альбом
    # даже в DRAFT / COMPLETED — это даёт ему встроенную камеру в приложении.
    is_owner_join = actor_user_id is not None and actor_user_id == event.user_id
    if event.status != EventStatus.ACTIVE and not is_owner_join:
        await join_attempt_repo.record(
            session, event_id=event.id, ip_hash=ip_hash_, fingerprint_hash=fp_hash,
            short_code_tried=short_code, pin_tried=bool(pin),
            outcome=JoinAttemptOutcome.EVENT_CLOSED,
        )
        await _delay()
        raise ConflictError(
            "Ивент ещё не начался или уже завершён",
            details={"status": event.status.value},
        )

    # event.start_at nullable в модели — защищаемся от TypeError при сравнении.
    if (
        not is_owner_join
        and event.start_at is not None
        and event.start_at > datetime.now(timezone.utc)
    ):
        await join_attempt_repo.record(
            session, event_id=event.id, ip_hash=ip_hash_, fingerprint_hash=fp_hash,
            short_code_tried=short_code, pin_tried=bool(pin),
            outcome=JoinAttemptOutcome.EVENT_CLOSED,
        )
        await _delay()
        raise ConflictError(
            "Ивент ещё не начался",
            details={"start_at": event.start_at.isoformat()},
        )

    # PIN-проверка: только если событие требует PIN и это не invite-bypass и не хост.
    if event.pin_enabled and event.entry_pin and not invite_bypass and not is_owner_join:
        if not pin:
            await join_attempt_repo.record(
                session, event_id=event.id, ip_hash=ip_hash_, fingerprint_hash=fp_hash,
                short_code_tried=short_code, pin_tried=False,
                outcome=JoinAttemptOutcome.PIN_REQUIRED,
            )
            await _delay()
            raise PinRequiredError("Введите PIN события")
        if pin != event.entry_pin:
            try:
                await _register_bad_pin(fp_hash)
            except RateLimitError:
                await join_attempt_repo.record(
                    session, event_id=event.id, ip_hash=ip_hash_, fingerprint_hash=fp_hash,
                    short_code_tried=short_code, pin_tried=True,
                    outcome=JoinAttemptOutcome.RATE_LIMITED,
                )
                await _delay()
                raise
            await join_attempt_repo.record(
                session, event_id=event.id, ip_hash=ip_hash_, fingerprint_hash=fp_hash,
                short_code_tried=short_code, pin_tried=True,
                outcome=JoinAttemptOutcome.BAD_PIN,
            )
            await _maybe_notify_suspicious(session, event)
            await _delay()
            raise BadPinError("Неверный PIN")

    # 1. Авторизованный flow — поиск по user_id (существующий гость → возвращаем сразу)
    if actor_user_id is not None:
        existing = await guest_repo.get_by_event_and_user(session, event.id, actor_user_id)
        if existing is not None:
            if name and name != existing.name:
                existing.name = name[:40]
                await session.commit()
            frames_used = await frame_repo.count_uploaded_for_guest(session, existing.id)
            await join_attempt_repo.record(
                session, event_id=event.id, ip_hash=ip_hash_, fingerprint_hash=fp_hash,
                short_code_tried=short_code, pin_tried=bool(pin),
                outcome=JoinAttemptOutcome.OK,
            )
            await _delay()
            return _build_session_out(existing, frames_used)

    # 2. Анонимный (или авторизованный без существующего guest) — fallback на fingerprint
    existing = await guest_repo.get_by_event_and_fingerprint(session, event.id, fingerprint)
    if existing is not None:
        if actor_user_id is not None and existing.user_id is None:
            existing.user_id = actor_user_id
            await session.commit()
        frames_used = await frame_repo.count_uploaded_for_guest(session, existing.id)
        await join_attempt_repo.record(
            session, event_id=event.id, ip_hash=ip_hash_, fingerprint_hash=fp_hash,
            short_code_tried=short_code, pin_tried=bool(pin),
            outcome=JoinAttemptOutcome.OK,
        )
        await _delay()
        return _build_session_out(existing, frames_used)

    # 3. Проверяем cap «3 новых альбома / 24ч» перед созданием нового гостя.
    # Invite-bypass и хост события не считаются.
    if not invite_bypass and not is_owner_join:
        try:
            await _check_album_cap(session, fp_hash, event.id)
        except AlbumCapError:
            await join_attempt_repo.record(
                session, event_id=event.id, ip_hash=ip_hash_, fingerprint_hash=fp_hash,
                short_code_tried=short_code, pin_tried=bool(pin),
                outcome=JoinAttemptOutcome.ALBUM_CAP,
            )
            await _delay()
            raise

    guests_count = await event_repo.count_guests(session, event.id)
    if guests_count >= event.settings.max_guests:
        await join_attempt_repo.record(
            session, event_id=event.id, ip_hash=ip_hash_, fingerprint_hash=fp_hash,
            short_code_tried=short_code, pin_tried=bool(pin),
            outcome=JoinAttemptOutcome.GUEST_LIMIT,
        )
        await _delay()
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

    # Свяжем consent-записи, сделанные с этим fingerprint ДО создания Guest.
    from app.repos import consent_repo as _consent_repo
    if fp_hash:
        await _consent_repo.link_fingerprint_to_guest(session, fp_hash, guest.id)

    # Build result before commit while event/settings are still loaded in session
    result = _build_session_out(guest, frames_used=0, event=event)

    await session.commit()

    # Audit: успешный OK. Delay ставим после commit, чтобы не держать транзакцию.
    await join_attempt_repo.record(
        session, event_id=event.id, ip_hash=ip_hash_, fingerprint_hash=fp_hash,
        short_code_tried=short_code, pin_tried=bool(pin),
        outcome=JoinAttemptOutcome.OK,
    )
    await _delay()

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


async def anonymize_guest(session: AsyncSession, guest_id: UUID) -> dict:
    """Обезличивание Гостя по запросу через поддержку (privacy v2.2 §11).

    Что делает:
    - удаляет caption и voice-файлы у всех фреймов этого Гостя (это его ПД);
    - удаляет аватар в S3;
    - обезличивает записи ConsentRecord этого Гостя (fingerprint_hash → NULL);
    - удаляет Guest → Frame.guest_id становится NULL (SET NULL каскад).

    Само фото остаётся в альбоме — на основании законных интересов Хоста
    и других участников События (privacy v2.2 §10 п.4 обоснование).
    """
    from sqlalchemy import select, update
    from app.domain.models import Frame
    from app.domain.models.models import ConsentRecord, JoinAttempt

    guest = await guest_repo.get_by_id(session, guest_id)
    if guest is None:
        raise NotFoundError("Guest not found")

    # 1) voice + caption у фреймов Гостя
    frames_stmt = select(Frame).where(Frame.guest_id == guest_id)
    frames = list((await session.execute(frames_stmt)).scalars().all())
    voice_deleted = 0
    for f in frames:
        if f.voice_s3_key:
            s3_client.delete_object(f.voice_s3_key)
            voice_deleted += 1
            f.voice_s3_key = None
            f.voice_duration_ms = None
            f.voice_peaks = None
        f.caption = None

    # 2) аватар в S3
    if guest.avatar_key:
        s3_client.delete_object(guest.avatar_key)

    # 3) ConsentRecord — обезличиваем fingerprint_hash по этому Гостю
    #    (guest_id обнулится каскадом CASCADE при удалении Guest)
    await session.execute(
        update(ConsentRecord)
        .where(ConsentRecord.guest_id == guest_id)
        .values(fingerprint_hash=None, ip_hash=None, user_agent=None)
    )

    # 4) JoinAttempt — обезличиваем fingerprint по event Гостя (best effort)
    await session.execute(
        update(JoinAttempt)
        .where(JoinAttempt.fingerprint_hash == hash_fingerprint(guest.fingerprint))
        .values(fingerprint_hash=None)
    )

    # 5) сам Guest удаляется → Frame.guest_id становится NULL (SET NULL)
    event_id = guest.event_id
    guest_name = guest.name
    await session.delete(guest)
    await session.commit()

    logger.info(
        "guest_anonymized",
        guest_id=str(guest_id),
        event_id=str(event_id),
        frames=len(frames),
        voice_deleted=voice_deleted,
        guest_name=guest_name[:2] + "***",
    )
    return {
        "guest_id": str(guest_id),
        "event_id": str(event_id),
        "frames_anonymized": len(frames),
        "voice_files_deleted": voice_deleted,
    }
