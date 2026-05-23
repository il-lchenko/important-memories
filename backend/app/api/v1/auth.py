from fastapi import APIRouter, Request

from app.api.deps import SessionDep
from app.domain.schemas.auth import (
    EmailRequestIn,
    EmailRequestOut,
    EmailVerifyIn,
    RefreshIn,
    TokenOut,
)
from app.services import auth_service

router = APIRouter()


def _client_ip(request: Request) -> str:
    fwd = request.headers.get("x-forwarded-for")
    if fwd:
        return fwd.split(",")[0].strip()
    return request.client.host if request.client else "unknown"


@router.post("/email/request", response_model=EmailRequestOut)
async def request_email_otp(
    payload: EmailRequestIn,
    request: Request,
    session: SessionDep,
) -> EmailRequestOut:
    return await auth_service.request_otp(session, payload.email, _client_ip(request))


@router.post("/email/verify", response_model=TokenOut)
async def verify_email_otp(
    payload: EmailVerifyIn,
    session: SessionDep,
) -> TokenOut:
    return await auth_service.verify_otp(session, payload.email, payload.code)


@router.post("/refresh", response_model=TokenOut)
async def refresh_token(
    payload: RefreshIn,
    session: SessionDep,
) -> TokenOut:
    return await auth_service.refresh(session, payload.refresh_token)
