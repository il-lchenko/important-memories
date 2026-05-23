from dataclasses import dataclass
from typing import Annotated
from uuid import UUID

from fastapi import Depends, Header
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.db import get_session
from app.core.errors import AuthError
from app.core.security import TokenDecodeError, decode_token
from app.domain.models import Guest
from app.repos import guest_repo

SessionDep = Annotated[AsyncSession, Depends(get_session)]


async def get_current_user_id(
    authorization: Annotated[str | None, Header()] = None,
) -> UUID:
    if not authorization or not authorization.lower().startswith("bearer "):
        raise AuthError("Missing bearer token")
    token = authorization.split(" ", 1)[1].strip()
    try:
        return decode_token(token, expected_type="access")
    except TokenDecodeError as exc:
        raise AuthError(str(exc)) from exc


CurrentUserId = Annotated[UUID, Depends(get_current_user_id)]


async def get_current_guest(
    session: SessionDep,
    x_guest_token: Annotated[str | None, Header()] = None,
) -> Guest:
    if not x_guest_token:
        raise AuthError("Missing X-Guest-Token header")
    guest = await guest_repo.get_by_token(session, x_guest_token)
    if guest is None:
        raise AuthError("Invalid guest token")
    return guest


CurrentGuest = Annotated[Guest, Depends(get_current_guest)]


@dataclass
class Actor:
    user_id: UUID | None
    guest: Guest | None


async def get_current_actor(
    session: SessionDep,
    authorization: Annotated[str | None, Header()] = None,
    x_guest_token: Annotated[str | None, Header()] = None,
) -> Actor:
    if authorization and authorization.lower().startswith("bearer "):
        token = authorization.split(" ", 1)[1].strip()
        try:
            user_id = decode_token(token, expected_type="access")
            return Actor(user_id=user_id, guest=None)
        except TokenDecodeError as exc:
            raise AuthError(str(exc)) from exc
    if x_guest_token:
        guest = await guest_repo.get_by_token(session, x_guest_token)
        if guest is None:
            raise AuthError("Invalid guest token")
        return Actor(user_id=None, guest=guest)
    raise AuthError("Authentication required")


CurrentActor = Annotated[Actor, Depends(get_current_actor)]
