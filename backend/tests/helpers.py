from datetime import datetime, timedelta, timezone

from httpx import AsyncClient
from sqlalchemy import select

from app.core.db import SessionLocal
from app.core.security import hash_secret
from app.domain.models import EmailCode


async def _seed_code(email: str, code: str = "111111") -> None:
    async with SessionLocal() as s:
        s.add(
            EmailCode(
                email=email,
                code_hash=hash_secret(code),
                expires_at=datetime.now(timezone.utc) + timedelta(minutes=15),
            )
        )
        await s.commit()


async def authenticate(client: AsyncClient, email: str = "host@example.com") -> str:
    """Bypass /auth/email/request to avoid SMTP and rate-limit. Returns access_token."""
    await _seed_code(email, "111111")
    response = await client.post(
        "/api/v1/auth/email/verify", json={"email": email, "code": "111111"}
    )
    assert response.status_code == 200, response.text
    return response.json()["access_token"]


def auth_headers(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


def future_event_payload(title: str = "Test event") -> dict:
    now = datetime.now(timezone.utc)
    return {
        "title": title,
        "start_at": (now + timedelta(days=10)).isoformat(),
        "end_at": (now + timedelta(days=11)).isoformat(),
        "event_type": "wedding",
    }


def fp(seed: str = "1") -> str:
    """Валидный fingerprint (8..64 hex) для тестов. Раньше в тестах писали
    'fp-1'/'fp-2', но новый Pydantic-валидатор требует hex-строку."""
    # 8-hex достаточно — регекс `^[a-fA-F0-9]{8,64}$` пропустит.
    raw = "".join(f"{ord(c):02x}" for c in seed)[:8].ljust(8, "0")
    return raw
