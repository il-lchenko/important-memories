from uuid import UUID

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.domain.models import Payment


async def get_by_id(session: AsyncSession, payment_id: UUID) -> Payment | None:
    return await session.get(Payment, payment_id)


async def get_by_idempotency_key(session: AsyncSession, key: str) -> Payment | None:
    stmt = select(Payment).where(Payment.idempotency_key == key)
    return (await session.execute(stmt)).scalar_one_or_none()


async def get_by_yookassa_id(session: AsyncSession, yookassa_id: str) -> Payment | None:
    stmt = select(Payment).where(Payment.yookassa_id == yookassa_id)
    return (await session.execute(stmt)).scalar_one_or_none()


async def create(session: AsyncSession, payment: Payment) -> Payment:
    session.add(payment)
    await session.flush()
    return payment
