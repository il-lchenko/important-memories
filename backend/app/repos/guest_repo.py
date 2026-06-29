from uuid import UUID

from sqlalchemy import desc, func, select, update
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


async def get_by_event_and_user(
    session: AsyncSession, event_id: UUID, user_id: UUID
) -> Guest | None:
    """Найти существующего invited-гостя того же юзера в этом событии."""
    stmt = (
        select(Guest)
        .options(selectinload(Guest.event).selectinload(Event.settings))
        .where(Guest.event_id == event_id, Guest.user_id == user_id)
    )
    return (await session.execute(stmt)).scalar_one_or_none()


async def create(session: AsyncSession, guest: Guest) -> Guest:
    session.add(guest)
    await session.flush()
    return guest


async def backfill_user_id_by_fingerprint(
    session: AsyncSession, fingerprint: str, user_id: UUID
) -> int:
    """При регистрации юзера: проставить user_id на всех анонимных guests
    с этим fingerprint (= того же устройства). Возвращает кол-во привязанных гостей."""
    stmt = (
        update(Guest)
        .where(Guest.fingerprint == fingerprint, Guest.user_id.is_(None))
        .values(user_id=user_id)
        .execution_options(synchronize_session=False)
    )
    result = await session.execute(stmt)
    return int(result.rowcount or 0)


async def list_invited_events_for_user(
    session: AsyncSession, user_id: UUID, *, exclude_owned: bool = True
) -> list[tuple[Event, int, int]]:
    """Список Event-ов где юзер был гостем (invited).
    Возвращает [(event, my_frames_count, total_uploaded)] отсортированный по joined_at desc.
    Если exclude_owned=True — исключает события где user является хостом."""
    from app.domain.models import Frame, FrameStatus

    # Базовый подзапрос — Guest.id для текущего user (последний по joined_at в событии)
    base_q = (
        select(
            Guest.event_id,
            func.max(Guest.joined_at).label("last_joined"),
        )
        .where(Guest.user_id == user_id)
        .group_by(Guest.event_id)
    ).subquery()

    stmt = (
        select(Event)
        .options(selectinload(Event.settings))
        .join(base_q, base_q.c.event_id == Event.id)
        .order_by(desc(base_q.c.last_joined))
    )
    if exclude_owned:
        stmt = stmt.where(Event.user_id != user_id)

    events = list((await session.execute(stmt)).scalars().all())

    # Для каждого события — посчитать кадры юзера + общее количество кадров
    results: list[tuple[Event, int, int]] = []
    for event in events:
        my_frames_stmt = (
            select(func.count(Frame.id))
            .join(Guest, Guest.id == Frame.guest_id)
            .where(
                Frame.event_id == event.id,
                Guest.user_id == user_id,
                Frame.status != FrameStatus.DELETED,
            )
        )
        total_frames_stmt = select(func.count(Frame.id)).where(
            Frame.event_id == event.id,
            Frame.status == FrameStatus.UPLOADED,
        )
        my_count = int((await session.execute(my_frames_stmt)).scalar_one())
        total_count = int((await session.execute(total_frames_stmt)).scalar_one())
        results.append((event, my_count, total_count))

    return results


async def update_name(session: AsyncSession, guest_id: UUID, name: str) -> None:
    stmt = update(Guest).where(Guest.id == guest_id).values(name=name)
    await session.execute(stmt)
