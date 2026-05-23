from datetime import datetime, timedelta, timezone
from typing import Any, Literal
from uuid import UUID

import bcrypt
from jose import JWTError, jwt

from app.core.config import settings

TokenType = Literal["access", "refresh"]

_BCRYPT_MAX_BYTES = 72


def _prep(value: str) -> bytes:
    return value.encode("utf-8")[:_BCRYPT_MAX_BYTES]


def hash_secret(value: str) -> str:
    return bcrypt.hashpw(_prep(value), bcrypt.gensalt()).decode("utf-8")


def verify_secret(value: str, hashed: str) -> bool:
    try:
        return bcrypt.checkpw(_prep(value), hashed.encode("utf-8"))
    except (ValueError, TypeError):
        return False


def _create_token(subject: str, token_type: TokenType, ttl: timedelta) -> str:
    now = datetime.now(timezone.utc)
    payload: dict[str, Any] = {
        "sub": subject,
        "type": token_type,
        "iat": int(now.timestamp()),
        "exp": int((now + ttl).timestamp()),
    }
    return jwt.encode(
        payload,
        settings.JWT_SECRET.get_secret_value(),
        algorithm=settings.JWT_ALGORITHM,
    )


def create_access_token(user_id: UUID) -> str:
    return _create_token(
        str(user_id),
        "access",
        timedelta(minutes=settings.JWT_ACCESS_TTL_MIN),
    )


def create_refresh_token(user_id: UUID) -> str:
    return _create_token(
        str(user_id),
        "refresh",
        timedelta(days=settings.JWT_REFRESH_TTL_DAYS),
    )


class TokenDecodeError(Exception):
    pass


def decode_token(token: str, expected_type: TokenType) -> UUID:
    try:
        payload = jwt.decode(
            token,
            settings.JWT_SECRET.get_secret_value(),
            algorithms=[settings.JWT_ALGORITHM],
        )
    except JWTError as exc:
        raise TokenDecodeError("invalid token") from exc

    if payload.get("type") != expected_type:
        raise TokenDecodeError(f"expected {expected_type} token")

    sub = payload.get("sub")
    if not sub:
        raise TokenDecodeError("missing subject")

    try:
        return UUID(sub)
    except ValueError as exc:
        raise TokenDecodeError("invalid subject") from exc
