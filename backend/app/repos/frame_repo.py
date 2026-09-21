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


async def count_uploaded_for_guest(session: AsyncSession, guest_id: UUID) -> int:
    stmt = select(func.count(Frame.id)).where(
        Frame.guest_id == guest_id,
        Frame.status == FrameStatus.UPLOADED,
    )
    return int((await session.execute(stmt)).scalar_one())


async def count_pending_for_guest(session: AsyncSession, guest_id: UUID) -> int:
    """PENDING кадры — уже зарезервированы presign'ом, но ещё не залиты в S3.
    Учитываем в квоте, чтобы конкурентные presign не пробили лимит."""
    stmt = select(func.count(Frame.id)).where(
        Frame.guest_id == guest_id,
        Frame.status == FrameStatus.PENDING,
    )
    return int((await session.execute(stmt)).scalar_one())


async def find_by_upload_hash(
    session: AsyncSession, event_id: UUID, upload_hash: str
) -> Frame | None:
    """Ищет неудалённый кадр с таким же SHA-256 в рамках события — для дедупа
    gallery-uploads. Возвращает первый найденный (partial unique index гарантирует ≤1)."""
    stmt = select(Frame).where(
        Frame.event_id == event_id,
        Frame.upload_hash == upload_hash,
        Frame.status != FrameStatus.DELETED,
    ).limit(1)
    return (await session.execute(stmt)).scalar_one_or_none()
