from secrets import token_urlsafe

from sqlalchemy.ext.asyncio import AsyncSession

from app.core.errors import ConflictError, NotFoundError
from app.domain.models import Event, EventStatus, Guest
from app.domain.schemas.events import EventSettingsOut
from app.domain.schemas.guests import GuestEventOut, GuestSessionOut
from app.infra import fcm_client
from app.repos import device_repo, event_repo, frame_repo, guest_repo


def _build_session_out_direct(guest: Guest, event: Event, frames_used: int) -> GuestSessionOut:
    """Build session output using an already-loaded event object (avoids lazy-load after commit)."""
    s = event.settings
    remaining = max(0, s.frames_per_guest - frames_used)
    return GuestSessionOut(
        guest_id=guest.id,
        guest_token=guest.guest_token,
        event=GuestEventOut(
            id=event.id,
            title=event.title,
            status=event.status.value,
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


def _build_session_out(guest: Guest, frames_used: int) -> GuestSessionOut:
    event = guest.event
    s = event.settings
    remaining = max(0, s.frames_per_guest - frames_used)
    return GuestSessionOut(
        guest_id=guest.id,
        guest_token=guest.guest_token,
        event=GuestEventOut(
            id=event.id,
            title=event.title,
            status=event.status.value,
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
    session: AsyncSession, short_code: str, name: str, fingerprint: str
) -> GuestSessionOut:
    event = await event_repo.get_by_short_code(session, short_code)
    if event is None:
        raise NotFoundError("Event not found", details={"short_code": short_code})

    if event.status != EventStatus.ACTIVE:
        raise ConflictError(
            "Ивент ещё не начался или уже завершён",
            details={"status": event.status.value},
        )

    existing = await guest_repo.get_by_event_and_fingerprint(session, event.id, fingerprint)
    if existing is not None:
        frames_used = await frame_repo.count_non_deleted_for_guest(session, existing.id)
        return _build_session_out(existing, frames_used)

    guests_count = await event_repo.count_guests(session, event.id)
    if guests_count >= event.settings.max_guests:
        raise ConflictError(
            "Guest limit reached",
            details={"max_guests": event.settings.max_guests},
        )

    guest = Guest(
        event_id=event.id,
        name=name,
        guest_token=token_urlsafe(32),
        fingerprint=fingerprint,
    )
    await guest_repo.create(session, guest)

    # Build result before commit while event/settings are still loaded in session
    result = _build_session_out_direct(guest, event, frames_used=0)

    await session.commit()

    # Notify host that a new guest joined
    host_tokens = await device_repo.get_tokens_for_user(session, event.user_id)
    if host_tokens:
        guests_total = guests_count + 1
        await fcm_client.send_multicast(
            tokens=host_tokens,
            title=event.title,
            body=f"{name} присоединился к плёнке · {guests_total} гостей",
            data={"event_id": str(event.id), "type": "guest_joined"},
        )

    return result


async def get_session_state(session: AsyncSession, guest_token: str) -> GuestSessionOut:
    guest = await guest_repo.get_by_token(session, guest_token)
    if guest is None:
        raise NotFoundError("Guest session not found")
    frames_used = await frame_repo.count_non_deleted_for_guest(session, guest.id)
    return _build_session_out(guest, frames_used)
