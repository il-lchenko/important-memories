from datetime import datetime, timezone

from sqlalchemy import select, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.domain.models import EmailCode


async def create(
    session: AsyncSession,
    email: str,
    code_hash: str,
    expires_at: datetime,
) -> EmailCode:
    code = EmailCode(email=email, code_hash=code_hash, expires_at=expires_at)
    session.add(code)
    await session.flush()
    return code


async def find_active(session: AsyncSession, email: str) -> EmailCode | None:
    now = datetime.now(timezone.utc)
    stmt = (
        select(EmailCode)
        .where(
            EmailCode.email == email,
            EmailCode.consumed.is_(False),
            EmailCode.expires_at > now,
        )
        .order_by(EmailCode.created_at.desc())
        .limit(1)
    )
    result = await session.execute(stmt)
    return result.scalar_one_or_none()


async def increment_attempts(session: AsyncSession, code: EmailCode) -> None:
    code.attempts += 1
    await session.flush()


async def consume(session: AsyncSession, code: EmailCode) -> None:
    code.consumed = True
    await session.flush()


async def invalidate_active_for_email(session: AsyncSession, email: str) -> None:
    """Mark all active codes for email as consumed (used when issuing a fresh code)."""
    now = datetime.now(timezone.utc)
    stmt = (
        update(EmailCode)
        .where(
            EmailCode.email == email,
            EmailCode.consumed.is_(False),
            EmailCode.expires_at > now,
        )
        .values(consumed=True)
    )
    await session.execute(stmt)
