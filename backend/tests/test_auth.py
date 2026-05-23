from datetime import datetime, timedelta, timezone

import pytest
from httpx import AsyncClient
from sqlalchemy import select

from app.core.db import SessionLocal
from app.core.security import hash_secret
from app.domain.models import EmailCode, User


async def _get_active_code_hash(email: str) -> EmailCode | None:
    async with SessionLocal() as s:
        result = await s.execute(
            select(EmailCode).where(EmailCode.email == email).order_by(EmailCode.created_at.desc())
        )
        return result.scalars().first()


async def _seed_code(email: str, code: str, ttl_min: int = 15) -> None:
    async with SessionLocal() as s:
        s.add(
            EmailCode(
                email=email,
                code_hash=hash_secret(code),
                expires_at=datetime.now(timezone.utc) + timedelta(minutes=ttl_min),
            )
        )
        await s.commit()


@pytest.mark.asyncio
async def test_request_otp_creates_code_and_returns_200(client: AsyncClient) -> None:
    response = await client.post("/api/v1/auth/email/request", json={"email": "user@example.com"})
    assert response.status_code == 200, response.text
    body = response.json()
    assert body["ok"] is True
    assert body["expires_in"] == 15 * 60

    code = await _get_active_code_hash("user@example.com")
    assert code is not None
    assert code.consumed is False


@pytest.mark.asyncio
async def test_request_otp_invalid_email_returns_422(client: AsyncClient) -> None:
    response = await client.post("/api/v1/auth/email/request", json={"email": "not-an-email"})
    assert response.status_code == 422


@pytest.mark.asyncio
async def test_request_otp_cooldown_blocks_second_request(client: AsyncClient) -> None:
    await client.post("/api/v1/auth/email/request", json={"email": "a@example.com"})
    second = await client.post("/api/v1/auth/email/request", json={"email": "a@example.com"})
    assert second.status_code == 409
    assert second.json()["error"]["code"] == "CONFLICT"


@pytest.mark.asyncio
async def test_verify_otp_success_returns_tokens_and_creates_user(client: AsyncClient) -> None:
    email = "new@example.com"
    code = "123456"
    await _seed_code(email, code)

    response = await client.post(
        "/api/v1/auth/email/verify", json={"email": email, "code": code}
    )
    assert response.status_code == 200, response.text
    data = response.json()
    assert data["token_type"] == "bearer"
    assert data["access_token"]
    assert data["refresh_token"]
    assert data["user_id"]

    async with SessionLocal() as s:
        user = (await s.execute(select(User).where(User.email == email))).scalar_one()
        assert user.last_login_at is not None


@pytest.mark.asyncio
async def test_verify_otp_wrong_code_returns_401(client: AsyncClient) -> None:
    await _seed_code("a@example.com", "111111")
    response = await client.post(
        "/api/v1/auth/email/verify", json={"email": "a@example.com", "code": "999999"}
    )
    assert response.status_code == 401
    assert response.json()["error"]["code"] == "UNAUTHORIZED"


@pytest.mark.asyncio
async def test_verify_otp_no_active_code_returns_401(client: AsyncClient) -> None:
    response = await client.post(
        "/api/v1/auth/email/verify", json={"email": "nobody@example.com", "code": "123456"}
    )
    assert response.status_code == 401


@pytest.mark.asyncio
async def test_refresh_with_valid_token_issues_new_tokens(client: AsyncClient) -> None:
    email = "rotate@example.com"
    await _seed_code(email, "123456")
    verify_resp = await client.post(
        "/api/v1/auth/email/verify", json={"email": email, "code": "123456"}
    )
    refresh = verify_resp.json()["refresh_token"]

    response = await client.post("/api/v1/auth/refresh", json={"refresh_token": refresh})
    assert response.status_code == 200, response.text
    assert response.json()["access_token"]


@pytest.mark.asyncio
async def test_refresh_with_invalid_token_returns_401(client: AsyncClient) -> None:
    response = await client.post(
        "/api/v1/auth/refresh", json={"refresh_token": "not.a.valid.jwt"}
    )
    assert response.status_code == 401
