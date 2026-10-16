from datetime import datetime, timedelta, timezone
from io import BytesIO
from secrets import token_urlsafe
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
from app.repos import device_repo, event_repo, user_repo
from app.services import entitlement_service
from app.services.event_lifecycle import completion_due
from app.services.payment_service import (
    CUSTOM_MAX_GUESTS,
    custom_per_guest_kopecks,
    pricing_v2_active,
    EXTEND_OPTIONS,
    PAID_TIERS,
    PLAN_PRICES_KOPECKS,
)

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

# Default storage retention (days) per plan.
_PLAN_RETENTION_DAYS: dict[Plan, int] = {
    Plan.FREE: 30,
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

# v2: 240 дней для 250+ гостей съедали маржу сильнее, чем у тарифа на 200.
_RETENTION_DAYS_V2: dict[Plan, int] = {
    Plan.P250: 180,
    Plan.CUSTOM: 180,
    Plan.UNLIMITED: 180,
}


def retention_days(plan: Plan) -> int:
    if pricing_v2_active() and plan in _RETENTION_DAYS_V2:
        return _RETENTION_DAYS_V2[plan]
    return _PLAN_RETENTION_DAYS.get(plan, 60)


def price_for_guests(guests: int) -> int:
    """Цена в копейках для произвольного числа гостей; -1 — нужен B2B-запрос."""
    if guests <= _PLAN_LIMITS[Plan.FREE]:
        return 0
    for plan in PAID_TIERS:
        if guests <= _PLAN_LIMITS[plan]:
            return PLAN_PRICES_KOPECKS[plan]
    if guests <= CUSTOM_MAX_GUESTS:
        top = PAID_TIERS[-1]
        return PLAN_PRICES_KOPECKS[top] + (guests - _PLAN_LIMITS[top]) * custom_per_guest_kopecks()
    return -1


def default_expires_at(plan: Plan, activated_at: datetime | None = None) -> datetime:
    """Compute expires_at for an event newly activated on `plan`."""
    base = activated_at or datetime.now(timezone.utc)
    return base + timedelta(days=retention_days(plan))


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
            uploads_enabled=s.uploads_enabled,
            uploads_window_ends_at=s.uploads_window_ends_at,
            qr_style=s.qr_style,
            title_font=s.title_font,
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
        ext = EXTEND_OPTIONS.get(payload.storage_extension)
        if ext is not None:
            extra_days = ext[0]
    base_days = retention_days(payload.plan)
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
        uploads_enabled=payload.uploads_enabled,
    )
    await event_repo.create(session, event)
    await session.commit()
    return _to_out(event)


async def _auto_complete_if_expired(session: AsyncSession, event: Event) -> None:
    """Self-healing для host-app списка: тот же принцип, что в guest_service."""
    if completion_due(event, datetime.now(timezone.utc)):
        event.status = EventStatus.COMPLETED


async def list_events(session: AsyncSession, user_id: UUID) -> list[EventOut]:
    from sqlalchemy import func, select
    from app.domain.models import Frame, FrameStatus, Guest

    events = await event_repo.list_for_user(session, user_id)
    if not events:
        return []
    # Batch self-heal: закроем все истёкшие ACTIVE события за один коммит.
    changed = False
    now = datetime.now(timezone.utc)
    for e in events:
        if completion_due(e, now):
            e.status = EventStatus.COMPLETED
            changed = True
    if changed:
        await session.commit()

    event_ids = [e.id for e in events]
    # Гость «активный» = у него есть хотя бы один uploaded-кадр. Считаем DISTINCT
    # напрямую по таблице frames — надёжнее чем Guest.frames_used (может рассинхрониться).
    g_rows = await session.execute(
        select(Frame.event_id, func.count(func.distinct(Frame.guest_id)))
        .where(Frame.event_id.in_(event_ids), Frame.status == FrameStatus.UPLOADED)
        .group_by(Frame.event_id)
    )
    # Считаем только фактически загруженные кадры — удалённые/pending исключены.
    f_rows = await session.execute(
        select(Frame.event_id, func.count(Frame.id))
        .where(Frame.event_id.in_(event_ids), Frame.status == FrameStatus.UPLOADED)
        .group_by(Frame.event_id)
    )
    guests_map = {r[0]: r[1] for r in g_rows}
    frames_map = {r[0]: r[1] for r in f_rows}
    return [_to_out(e, guests_map.get(e.id, 0), frames_map.get(e.id, 0)) for e in events]


async def get_event(session: AsyncSession, user_id: UUID, event_id: UUID) -> EventOut:
    from sqlalchemy import func, select
    from app.domain.models import Frame, FrameStatus

    event = await _load_owned(session, event_id, user_id)
    await _auto_complete_if_expired(session, event)
    if event in session.dirty:
        await session.commit()
    g = (await session.execute(
        select(func.count(func.distinct(Frame.guest_id)))
        .where(Frame.event_id == event_id, Frame.status == FrameStatus.UPLOADED)
    )).scalar_one()
    f = (await session.execute(
        select(func.count(Frame.id))
        .where(Frame.event_id == event_id, Frame.status == FrameStatus.UPLOADED)
    )).scalar_one()
    return _to_out(event, int(g), int(f))


async def update_settings(
    session: AsyncSession,
    user_id: UUID,
    event_id: UUID,
    payload: EventSettingsUpdateIn,
) -> EventOut:
    event = await _load_owned(session, event_id, user_id)
    if payload.plan is not None and event.status != EventStatus.DRAFT:
        raise ConflictError(
            "Тариф меняется только через оплату",
            details={"status": event.status.value},
        )
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
    # uploads_enabled НЕ в locked-fields списке выше: Хост должен иметь возможность
    # быстро отключить фичу при абьюзе, даже после присоединения гостей.
    if payload.uploads_enabled is not None:
        s.uploads_enabled = payload.uploads_enabled
    # Оформление тоже не блокируется: QR и шрифт меняются в любой момент.
    if payload.qr_style is not None:
        s.qr_style = payload.qr_style
    if payload.title_font is not None:
        s.title_font = payload.title_font

    reveal_changed = payload.reveal_mode is not None or payload.reveal_at is not None
    if reveal_changed and s.reveal_mode == RevealMode.DELAYED:
        if s.reveal_at is None:
            raise ConflictError("reveal_at is required for delayed reveal")
        if s.reveal_at <= datetime.now(timezone.utc):
            raise ConflictError("reveal_at must be in the future")

    await session.commit()
    if (
        reveal_changed
        and s.reveal_mode == RevealMode.DELAYED
        and s.reveal_at is not None
        and event.status == EventStatus.ACTIVE
    ):
        await queue.schedule_reveal(event.id, s.reveal_at)
    return _to_out(event)


async def activate_event(
    session: AsyncSession, user_id: UUID, event_id: UUID
) -> EventOut:
    """Бесплатная активация. Платные тарифы активирует только вебхук оплаты
    (или checkout в админ-режиме); админ может активировать любой черновик."""
    event = await _load_owned(session, event_id, user_id)
    if event.status != EventStatus.DRAFT:
        raise ConflictError(
            "Only draft events can be activated",
            details={"status": event.status.value},
        )
    user = await user_repo.get_by_id(session, user_id)
    await entitlement_service.ensure_can_activate(session, user, event)
    event.status = EventStatus.ACTIVE
    event.activated_at = datetime.now(timezone.utc)
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


async def get_public_share(
    session: AsyncSession, user_id: UUID, event_id: UUID
) -> str | None:
    """Возвращает текущий токен открытой ссылки или None, если Хост её не создавал."""
    event = await _load_owned(session, event_id, user_id)
    return event.public_share_token


async def enable_public_share(
    session: AsyncSession, user_id: UUID, event_id: UUID
) -> str:
    """Хост явно включает открытую ссылку. Действие фиксирует принятие
    ответственности за распространение (privacy v2.2 §10, оферта §7)."""
    event = await _load_owned(session, event_id, user_id)
    if event.status not in (EventStatus.COMPLETED, EventStatus.CANCELLED):
        raise ConflictError(
            "Открытая ссылка доступна после завершения альбома",
            details={"status": event.status.value},
        )
    if event.public_share_token is None:
        event.public_share_token = token_urlsafe(24)
        await session.commit()
    return event.public_share_token


async def disable_public_share(
    session: AsyncSession, user_id: UUID, event_id: UUID
) -> None:
    """Хост отключает открытую ссылку — токен обнуляется, старая ссылка сразу
    перестаёт работать (album_service проверяет NULL)."""
    event = await _load_owned(session, event_id, user_id)
    if event.public_share_token is not None:
        event.public_share_token = None
        await session.commit()


async def regenerate_public_share(
    session: AsyncSession, user_id: UUID, event_id: UUID
) -> str:
    event = await _load_owned(session, event_id, user_id)
    if event.status not in (EventStatus.COMPLETED, EventStatus.CANCELLED):
        raise ConflictError(
            "Открытая ссылка доступна после завершения альбома",
            details={"status": event.status.value},
        )
    event.public_share_token = token_urlsafe(24)
    await session.commit()
    return event.public_share_token


def build_qr_png(short_code: str, *, pin: str | None = None) -> tuple[str, bytes]:
    """Собирает QR-код с URL альбома. Если pin передан — включаем в URL как ?p=PIN,
    чтобы сканирование оставалось одношаговым (клиент подставляет PIN автоматом)."""
    base = f"{settings.PUBLIC_PWA_BASE_URL.rstrip('/')}/g/{short_code}"
    short_url = f"{base}?p={pin}" if pin else base
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
        event.start_at = payload.start_at
    if payload.reveal_mode is not None or payload.reveal_at is not None:
        s = event.settings
        if payload.reveal_mode is not None:
            s.reveal_mode = payload.reveal_mode
        if payload.reveal_at is not None:
            s.reveal_at = payload.reveal_at
        if s.reveal_mode == RevealMode.DELAYED:
            if s.reveal_at is None:
                raise ConflictError("reveal_at is required for delayed reveal")
            if s.reveal_at <= datetime.now(timezone.utc):
                raise ConflictError("reveal_at must be in the future")
        if s.reveal_mode == RevealMode.DELAYED and s.reveal_at is not None and event.status == EventStatus.ACTIVE:
            await queue.schedule_reveal(event.id, s.reveal_at)
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
    # Если PIN включён — встраиваем в QR, чтобы сканирование давало сразу
    # автосабмит (см. main.dart deep-link handler + PWA URLSearchParams).
    pin = event.entry_pin if event.pin_enabled else None
    return build_qr_png(event.short_code, pin=pin)


# Длительность пост-event окна для gallery-uploads. Три пресета (см. UploadsWindowIn).
_UPLOADS_WINDOW_DURATIONS: dict[str, timedelta] = {
    "2h":  timedelta(hours=2),
    "24h": timedelta(hours=24),
    "7d":  timedelta(days=7),
}


async def set_uploads_window(
    session: AsyncSession, user_id: UUID, event_id: UUID, duration: str
) -> datetime:
    """Хост открывает загрузку из галереи на завершённом событии.
    Возвращает новый uploads_window_ends_at."""
    event = await _load_owned(session, event_id, user_id)
    if event.status != EventStatus.COMPLETED:
        raise ConflictError(
            "Окно загрузки открывается только на завершённых событиях",
            details={"status": event.status.value},
        )
    delta = _UPLOADS_WINDOW_DURATIONS.get(duration)
    if delta is None:
        raise ConflictError(
            "Unsupported duration preset",
            details={"allowed": list(_UPLOADS_WINDOW_DURATIONS.keys())},
        )
    ends_at = datetime.now(timezone.utc) + delta
    event.settings.uploads_window_ends_at = ends_at
    await session.commit()
    return ends_at


async def clear_uploads_window(
    session: AsyncSession, user_id: UUID, event_id: UUID
) -> None:
    """Хост досрочно закрывает окно загрузки."""
    event = await _load_owned(session, event_id, user_id)
    if event.settings.uploads_window_ends_at is not None:
        event.settings.uploads_window_ends_at = None
        await session.commit()


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

    event = await _load_owned(session, event_id, user_id)

    ext = {"image/png": "png", "image/webp": "webp"}.get(content_type, "jpg")
    # Уникальный ключ на каждую загрузку: клиенты кэшируют картинки по пути,
    # и при постоянном cover.jpg новая обложка не показывалась.
    key = f"events/{event_id}/cover-{token_urlsafe(8)}.{ext}"
    s3_client.upload_bytes(key, data, content_type)

    previous = event.cover_url
    # Храним только S3-ключ — клиенту отдадим свежий presign в _to_out.
    event.cover_url = key
    await session.commit()
    if previous and not previous.startswith("http") and previous != key:
        try:
            s3_client.delete_object(previous)
        except Exception:
            pass
    return _to_out(event)
