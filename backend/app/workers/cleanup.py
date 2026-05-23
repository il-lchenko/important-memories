from datetime import datetime, timedelta, timezone

from sqlalchemy import select, update

from app.core.db import SessionLocal
from app.core.logging import logger
from app.domain.models import Frame, FrameStatus


async def retry_failed_uploads(ctx: dict) -> int:
    """Mark pending frames older than 1 hour as deleted (their PUT never landed)."""
    cutoff = datetime.now(timezone.utc) - timedelta(hours=1)
    async with SessionLocal() as session:
        stmt = (
            update(Frame)
            .where(Frame.status == FrameStatus.PENDING, Frame.captured_at < cutoff)
            .values(status=FrameStatus.DELETED, deleted_at=datetime.now(timezone.utc))
        )
        result = await session.execute(stmt)
        await session.commit()
        count = result.rowcount or 0
    if count:
        logger.info("retry_failed_uploads_cleaned", count=count)
    return count


async def cleanup_expired_frames(ctx: dict) -> int:
    """Hard-delete soft-deleted frames older than 30 days (frees S3 storage).

    For MVP just clears the DB rows; the S3 sweep is a separate maintenance job.
    """
    cutoff = datetime.now(timezone.utc) - timedelta(days=30)
    async with SessionLocal() as session:
        stmt = select(Frame).where(
            Frame.status == FrameStatus.DELETED,
            Frame.deleted_at < cutoff,
        )
        frames = list((await session.execute(stmt)).scalars().all())
        for f in frames:
            await session.delete(f)
        await session.commit()
    if frames:
        logger.info("cleanup_expired_done", count=len(frames))
    return len(frames)
