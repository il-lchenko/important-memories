from fastapi import APIRouter

from app.api.deps import CurrentGuest, SessionDep
from app.core.errors import NotFoundError
from app.domain.models import EventStatus
from app.domain.schemas.guests import EventPreviewOut, GuestJoinIn, GuestSessionOut
from app.repos import event_repo
from app.services import guest_service

router = APIRouter()


@router.get("/events/{short_code}", response_model=EventPreviewOut)
async def get_event_preview(short_code: str, session: SessionDep) -> EventPreviewOut:
    event = await event_repo.get_by_short_code(session, short_code)
    if event is None or event.status == EventStatus.CANCELLED:
        raise NotFoundError("Event not found", details={"short_code": short_code})
    s = event.settings
    return EventPreviewOut(
        title=event.title,
        frames_per_guest=s.frames_per_guest,
        reveal_at=s.reveal_at,
        lut_preset=s.lut_preset.value,
        status=event.status.value,
    )


@router.post("/sessions", response_model=GuestSessionOut, status_code=201)
async def join_event(
    payload: GuestJoinIn,
    session: SessionDep,
) -> GuestSessionOut:
    return await guest_service.join(
        session,
        short_code=payload.short_code,
        name=payload.name,
        fingerprint=payload.fingerprint,
    )


@router.get("/sessions/me", response_model=GuestSessionOut)
async def get_my_session(
    guest: CurrentGuest,
    session: SessionDep,
) -> GuestSessionOut:
    return await guest_service.get_session_state(session, guest.guest_token)
