from uuid import UUID

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.domain.models import Event, Guest


async def get_by_token(session: AsyncSession, token: str) -> Guest | None:
    stmt = (
        select(Guest)
        .options(selectinload(Guest.event).selectinload(Event.settings))
        .where(Guest.guest_token == token)
    )
    return (await session.execute(stmt)).scalar_one_or_none()


async def get_by_event_and_fingerprint(
    session: AsyncSession, event_id: UUID, fingerprint: str
) -> Guest | None:
    stmt = (
        select(Guest)
        .options(selectinload(Guest.event).selectinload(Event.settings))
        .where(Guest.event_id == event_id, Guest.fingerprint == fingerprint)
    )
    return (await session.execute(stmt)).scalar_one_or_none()


async def create(session: AsyncSession, guest: Guest) -> Guest:
    session.add(guest)
    await session.flush()
    return guest
