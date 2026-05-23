from datetime import datetime, timezone
from uuid import UUID

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.domain.models import User


async def get_by_email(session: AsyncSession, email: str) -> User | None:
    result = await session.execute(select(User).where(User.email == email))
    return result.scalar_one_or_none()


async def get_by_id(session: AsyncSession, user_id: UUID) -> User | None:
    return await session.get(User, user_id)


async def create(session: AsyncSession, email: str) -> User:
    user = User(email=email)
    session.add(user)
    await session.flush()
    return user


async def touch_last_login(session: AsyncSession, user: User) -> None:
    user.last_login_at = datetime.now(timezone.utc)
    await session.flush()


async def get_or_create(session: AsyncSession, email: str) -> tuple[User, bool]:
    """Returns (user, is_new)."""
    existing = await get_by_email(session, email)
    if existing:
        return existing, False
    return await create(session, email), True
