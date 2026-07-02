from fastapi import APIRouter, Request

from app.api.deps import CurrentGuest, OptionalUserId, SessionDep
from app.core.errors import NotFoundError
from app.domain.models import EventStatus
from app.domain.schemas.guests import (
    EventPreviewOut,
    GuestJoinIn,
    GuestNameUpdateIn,
    GuestSessionOut,
)
from app.repos import event_repo
from app.services import guest_service
from app.services.event_service import _resolve_cover_url

router = APIRouter()


def _client_ip(request: Request) -> str | None:
    # Nginx sets X-Real-IP; fallback to raw client.
    xr = request.headers.get("x-real-ip")
    if xr:
        return xr.split(",")[0].strip()
    return request.client.host if request.client else None


@router.get("/events/{short_code}", response_model=EventPreviewOut)
async def get_event_preview(
    short_code: str, session: SessionDep, request: Request
) -> EventPreviewOut:
    event = await event_repo.get_by_short_code(session, short_code)
    if event is None or event.status == EventStatus.CANCELLED:
        # Same anti-bruteforce path as POST /sessions.
        await guest_service._register_short_code_failure(_client_ip(request))
        raise NotFoundError("Код не найден")
    s = event.settings
    return EventPreviewOut(
        title=event.title,
        frames_per_guest=s.frames_per_guest,
        reveal_at=s.reveal_at,
        start_at=event.start_at,
        lut_preset=s.lut_preset.value,
        status=event.status.value,
        cover_url=_resolve_cover_url(event.cover_url),
    )


@router.post("/sessions", response_model=GuestSessionOut, status_code=201)
async def join_event(
    payload: GuestJoinIn,
    session: SessionDep,
    user_id: OptionalUserId,
    request: Request,
) -> GuestSessionOut:
    return await guest_service.join(
        session,
        short_code=payload.short_code,
        name=payload.name,
        fingerprint=payload.fingerprint,
        actor_user_id=user_id,
        client_ip=_client_ip(request),
    )


@router.get("/sessions/me", response_model=GuestSessionOut)
async def get_my_session(
    guest: CurrentGuest,
    session: SessionDep,
) -> GuestSessionOut:
    return await guest_service.get_session_state(session, guest.guest_token)


@router.patch("/sessions/me", response_model=GuestSessionOut)
async def update_my_guest_name(
    payload: GuestNameUpdateIn,
    guest: CurrentGuest,
    session: SessionDep,
) -> GuestSessionOut:
    return await guest_service.update_guest_name(session, guest.guest_token, payload.name)
