from fastapi import APIRouter, Request

from app.api.deps import CurrentGuest, OptionalUserId, SessionDep
from app.core.client_ctx import client_ip, hash_fingerprint, hash_ip
from app.core.errors import NotFoundError, RateLimitError
from app.domain.models import EventStatus, JoinAttemptOutcome
from app.domain.schemas.guests import (
    EventPreviewOut,
    GuestAvatarPresignIn,
    GuestAvatarPresignOut,
    GuestJoinIn,
    GuestNameUpdateIn,
    GuestProfileUpdateIn,
    GuestSessionOut,
)
from app.repos import event_repo, join_attempt_repo
from app.services import guest_service, invite_service
from app.services.event_service import _resolve_cover_url
from pydantic import BaseModel, Field, field_validator
import re

_FP_RE = re.compile(r"^[a-fA-F0-9]{8,64}$")


class InviteJoinIn(BaseModel):
    """Payload для POST /guest/invites/{token}/join."""
    name: str | None = Field(default=None, max_length=40)
    fingerprint: str = Field(min_length=8, max_length=64)

    @field_validator("fingerprint")
    @classmethod
    def _v_fp(cls, v: str) -> str:
        if not _FP_RE.match(v):
            raise ValueError("fingerprint must be 8–64 hex characters")
        return v.lower()

router = APIRouter()


@router.get("/events/{short_code}", response_model=EventPreviewOut)
async def get_event_preview(
    short_code: str, session: SessionDep, request: Request
) -> EventPreviewOut:
    ip = client_ip(request)
    event = await event_repo.get_by_short_code(session, short_code)
    if event is None or event.status == EventStatus.CANCELLED:
        # Same anti-bruteforce path as POST /sessions — считаем bad_code.
        try:
            await guest_service._register_bad_code(ip, None)
        except RateLimitError:
            await join_attempt_repo.record(
                session, event_id=None, ip_hash=hash_ip(ip), fingerprint_hash=None,
                short_code_tried=short_code, pin_tried=False,
                outcome=JoinAttemptOutcome.RATE_LIMITED,
            )
            await guest_service._delay()
            raise
        await join_attempt_repo.record(
            session, event_id=None, ip_hash=hash_ip(ip), fingerprint_hash=None,
            short_code_tried=short_code, pin_tried=False,
            outcome=JoinAttemptOutcome.BAD_CODE,
        )
        await guest_service._delay()
        raise NotFoundError("Код не найден")
    # Self-healing: если end_at прошёл — status превратится в completed на месте.
    await guest_service.auto_complete_if_expired(session, event)
    s = event.settings
    return EventPreviewOut(
        title=event.title,
        frames_per_guest=s.frames_per_guest,
        reveal_at=s.reveal_at,
        start_at=event.start_at,
        lut_preset=s.lut_preset.value,
        status=event.status.value,
        cover_url=_resolve_cover_url(event.cover_url),
        pin_required=bool(event.pin_enabled and event.entry_pin),
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
        client_ip=client_ip(request),
        pin=payload.pin,
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


@router.patch("/profile", response_model=GuestSessionOut)
async def update_my_guest_profile(
    payload: GuestProfileUpdateIn,
    guest: CurrentGuest,
    session: SessionDep,
) -> GuestSessionOut:
    return await guest_service.update_guest_profile(
        session,
        guest.guest_token,
        name=payload.name,
        avatar_key=payload.avatar_key,
        bio=payload.bio,
    )


@router.post("/avatar/presign", response_model=GuestAvatarPresignOut)
async def presign_avatar(
    payload: GuestAvatarPresignIn,
    guest: CurrentGuest,
    session: SessionDep,
) -> GuestAvatarPresignOut:
    data = await guest_service.presign_avatar_upload(
        session, guest.guest_token, payload.content_type, payload.size_bytes
    )
    return GuestAvatarPresignOut(**data)


# ── Personal invites ────────────────────────────────────────────────────────
@router.get("/invites/{token}")
async def preview_invite(token: str, session: SessionDep) -> dict:
    """Preview приглашения — что за событие, для кого, ещё живо ли.
    Не создаёт сессию; фронт показывает подтверждение перед POST /join."""
    return await invite_service.preview_invite(session, token)


@router.post("/invites/{token}/join", response_model=GuestSessionOut, status_code=201)
async def join_by_invite(
    token: str,
    payload: InviteJoinIn,
    session: SessionDep,
    user_id: OptionalUserId,
    request: Request,
) -> GuestSessionOut:
    """Использовать invite: обходит PIN и лимит альбомов; помечает токен used."""
    return await invite_service.join_by_invite(
        session,
        token=token,
        name=payload.name,
        fingerprint=payload.fingerprint,
        actor_user_id=user_id,
        client_ip=client_ip(request),
    )
