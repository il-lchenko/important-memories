from datetime import datetime, timezone
from uuid import UUID

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.domain.models import DeviceToken, Platform


async def get_tokens_for_user(session: AsyncSession, user_id: UUID) -> list[str]:
    stmt = select(DeviceToken.token).where(DeviceToken.user_id == user_id)
    rows = (await session.execute(stmt)).scalars().all()
    return list(rows)


async def upsert(
    session: AsyncSession, user_id: UUID, platform: Platform, token: str
) -> DeviceToken:
    stmt = select(DeviceToken).where(DeviceToken.token == token)
    existing = (await session.execute(stmt)).scalar_one_or_none()
    if existing is not None:
        existing.user_id = user_id
        existing.platform = platform
        existing.last_used_at = datetime.now(timezone.utc)
        await session.flush()
        return existing
    device = DeviceToken(user_id=user_id, platform=platform, token=token)
    session.add(device)
    await session.flush()
    return device
