from dataclasses import dataclass
from typing import Annotated
from uuid import UUID

from fastapi import Depends
from fastapi.security import APIKeyHeader, HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.db import get_session
from app.core.errors import AuthError, PermissionDeniedError
from app.core.security import TokenDecodeError, decode_token
from app.domain.models import Guest, User
from app.repos import guest_repo, user_repo

SessionDep = Annotated[AsyncSession, Depends(get_session)]

# Схемы безопасности нужны для OpenAPI; ошибки отдаём сами (AuthError), как раньше.
_bearer_scheme = HTTPBearer(auto_error=False, scheme_name="HostBearer")
_guest_token_scheme = APIKeyHeader(
    name="X-Guest-Token", auto_error=False, scheme_name="GuestToken"
)
BearerCredentials = Annotated[HTTPAuthorizationCredentials | None, Depends(_bearer_scheme)]
GuestTokenHeader = Annotated[str | None, Depends(_guest_token_scheme)]


def _bearer_token(credentials: HTTPAuthorizationCredentials | None) -> str | None:
    if credentials is None:
        return None
    return credentials.credentials.strip() or None


async def get_current_user_id(credentials: BearerCredentials) -> UUID:
    token = _bearer_token(credentials)
    if token is None:
        raise AuthError("Missing bearer token")
    try:
        return decode_token(token, expected_type="access")
    except TokenDecodeError as exc:
        raise AuthError(str(exc)) from exc


CurrentUserId = Annotated[UUID, Depends(get_current_user_id)]


async def get_current_guest(
    session: SessionDep,
    x_guest_token: GuestTokenHeader,
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
    credentials: BearerCredentials,
    x_guest_token: GuestTokenHeader,
) -> Actor:
    token = _bearer_token(credentials)
    if token is not None:
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


async def get_optional_user_id(credentials: BearerCredentials) -> UUID | None:
    """Возвращает user_id если передан валидный Bearer токен, иначе None.
    Не бросает 401 — для эндпоинтов которые работают и для гостей, и для авторизованных."""
    token = _bearer_token(credentials)
    if token is None:
        return None
    try:
        return decode_token(token, expected_type="access")
    except TokenDecodeError:
        return None


OptionalUserId = Annotated[UUID | None, Depends(get_optional_user_id)]


async def require_admin(
    session: SessionDep,
    user_id: CurrentUserId,
) -> User:
    """Пропускает только пользователей с is_admin=True.

    Использовать в admin-only endpoints: /admin/promocodes, /admin/users/*.
    """
    user = await user_repo.get_by_id(session, user_id)
    if user is None or not user.is_admin:
        raise PermissionDeniedError("Admin only")
    return user


AdminUser = Annotated[User, Depends(require_admin)]
