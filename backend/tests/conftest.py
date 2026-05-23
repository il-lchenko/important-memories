import asyncio
import sys

if sys.platform == "win32":
    asyncio.set_event_loop_policy(asyncio.WindowsSelectorEventLoopPolicy())

from collections.abc import AsyncGenerator

import pytest
from httpx import ASGITransport, AsyncClient
from sqlalchemy import text

from app.core.db import engine
from app.core.redis import get_redis
from app.main import app


@pytest.fixture(scope="session")
async def client() -> AsyncGenerator[AsyncClient, None]:
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as ac:
        yield ac


@pytest.fixture(autouse=True)
async def _clean_db_and_redis():
    redis = get_redis()
    await redis.flushdb()
    async with engine.begin() as conn:
        await conn.execute(text(
            "TRUNCATE users, events, event_settings, guests, frames, "
            "payments, device_tokens, email_codes, reports, audit_log "
            "RESTART IDENTITY CASCADE"
        ))
    yield
