"""Repo для InviteToken — персональные приглашения в обход PIN и cap."""
from datetime import datetime, timezone
from uuid import UUID

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.domain.models import Event, InviteToken


async def create(session: AsyncSession, invite: InviteToken) -> InviteToken:
    session.add(invite)
    await session.flush()
    return invite


async def get_by_token(session: AsyncSession, token: str) -> InviteToken | None:
    stmt = select(InviteToken).where(InviteToken.token == token)
    return (await session.execute(stmt)).scalar_one_or_none()


async def get_by_token_with_event(
    session: AsyncSession, token: str
) -> tuple[InviteToken, Event] | None:
    stmt = (
        select(InviteToken, Event)
        .join(Event, Event.id == InviteToken.event_id)
        .options(selectinload(Event.settings))
        .where(InviteToken.token == token)
    )
    row = (await session.execute(stmt)).first()
    if not row:
        return None
    return row[0], row[1]


async def list_for_event(session: AsyncSession, event_id: UUID) -> list[InviteToken]:
    stmt = (
        select(InviteToken)
        .where(InviteToken.event_id == event_id)
        .order_by(InviteToken.created_at.desc())
    )
    return list((await session.execute(stmt)).scalars().all())


async def mark_used(
    session: AsyncSession, invite: InviteToken, guest_id: UUID
) -> None:
    invite.used_at = datetime.now(timezone.utc)
    invite.used_by_guest_id = guest_id
    await session.commit()


async def delete_by_id(session: AsyncSession, invite_id: UUID) -> None:
    from sqlalchemy import delete
    await session.execute(delete(InviteToken).where(InviteToken.id == invite_id))
    await session.commit()
