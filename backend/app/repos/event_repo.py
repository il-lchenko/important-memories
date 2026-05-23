from uuid import UUID

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.domain.models import Event


async def create(session: AsyncSession, event: Event) -> Event:
    session.add(event)
    await session.flush()
    return event


async def get_by_id(session: AsyncSession, event_id: UUID) -> Event | None:
    stmt = (
        select(Event)
        .options(selectinload(Event.settings))
        .where(Event.id == event_id)
    )
    return (await session.execute(stmt)).scalar_one_or_none()


async def get_by_short_code(session: AsyncSession, short_code: str) -> Event | None:
    stmt = (
        select(Event)
        .options(selectinload(Event.settings))
        .where(Event.short_code == short_code)
    )
    return (await session.execute(stmt)).scalar_one_or_none()


async def short_code_exists(session: AsyncSession, short_code: str) -> bool:
    stmt = select(Event.id).where(Event.short_code == short_code)
    return (await session.execute(stmt)).first() is not None


async def list_for_user(session: AsyncSession, user_id: UUID) -> list[Event]:
    stmt = (
        select(Event)
        .options(selectinload(Event.settings))
        .where(Event.user_id == user_id)
        .order_by(Event.created_at.desc())
    )
    return list((await session.execute(stmt)).scalars().all())


async def count_guests(session: AsyncSession, event_id: UUID) -> int:
    from sqlalchemy import func

    from app.domain.models import Guest

    stmt = select(func.count(Guest.id)).where(Guest.event_id == event_id)
    return int((await session.execute(stmt)).scalar_one())
