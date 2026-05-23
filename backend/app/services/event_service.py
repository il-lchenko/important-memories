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
)
from app.infra import fcm_client, queue, rate_limiter
from app.repos import device_repo, event_repo

_PLAN_LIMITS: dict[Plan, int] = {
    Plan.FREE: 5,
    Plan.P10: 10,
    Plan.P50: 50,
    Plan.P150: 150,
    Plan.UNLIMITED: 10_000,
}


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


def _to_out(event: Event) -> EventOut:
    s = event.settings
    return EventOut(
        id=event.id,
        short_code=event.short_code,
        title=event.title,
        start_at=event.start_at,
        end_at=event.end_at,
        event_type=event.event_type,
        status=event.status,
        cover_url=event.cover_url,
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
    )


async def create_event(
    session: AsyncSession, user_id: UUID, payload: EventCreateIn
) -> EventOut:
    await rate_limiter.check_and_incr(
        f"events:create:user:{user_id}", limit=5, window_sec=3600
    )
    short_code = await _allocate_short_code(session)
    event = Event(
        user_id=user_id,
        short_code=short_code,
        title=payload.title,
        start_at=payload.start_at,
        end_at=payload.end_at,
        event_type=payload.event_type,
        status=EventStatus.DRAFT,
    )
    event.settings = EventSettings(
        max_guests=_PLAN_LIMITS[payload.plan],
        frames_per_guest=payload.frames_per_guest,
        reveal_mode=payload.reveal_mode,
        lut_preset=payload.lut_preset or LutPreset.PORTRA400,
        plan=payload.plan,
        photo_format=payload.photo_format,
    )
    await event_repo.create(session, event)
    await session.commit()
    return _to_out(event)


async def list_events(session: AsyncSession, user_id: UUID) -> list[EventOut]:
    events = await event_repo.list_for_user(session, user_id)
    return [_to_out(e) for e in events]


async def get_event(session: AsyncSession, user_id: UUID, event_id: UUID) -> EventOut:
    event = await _load_owned(session, event_id, user_id)
    return _to_out(event)


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


async def generate_qr(
    session: AsyncSession, user_id: UUID, event_id: UUID
) -> tuple[str, bytes]:
    event = await _load_owned(session, event_id, user_id)
    return build_qr_png(event.short_code)
