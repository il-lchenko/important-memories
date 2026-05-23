from uuid import UUID

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.domain.models import Frame, FrameStatus


async def create(session: AsyncSession, frame: Frame) -> Frame:
    session.add(frame)
    await session.flush()
    return frame


async def get_by_id(session: AsyncSession, frame_id: UUID) -> Frame | None:
    return await session.get(Frame, frame_id)


async def count_non_deleted_for_guest(session: AsyncSession, guest_id: UUID) -> int:
    stmt = select(func.count(Frame.id)).where(
        Frame.guest_id == guest_id,
        Frame.status != FrameStatus.DELETED,
    )
    return int((await session.execute(stmt)).scalar_one())
