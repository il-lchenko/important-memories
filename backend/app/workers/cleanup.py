import asyncio
from datetime import datetime, timedelta, timezone

from sqlalchemy import select, update

from app.core.db import SessionLocal
from app.core.logging import logger
from app.domain.models import Frame, FrameStatus
from app.infra import s3_client


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


def _frame_keys(frame: Frame) -> list[str]:
    from app.workers.thumbnail import _preview_key, _thumbnail_key

    keys = []
    if frame.s3_key:
        keys += [frame.s3_key, _thumbnail_key(frame.s3_key), _preview_key(frame.s3_key)]
    if frame.voice_s3_key:
        keys.append(frame.voice_s3_key)
    return keys


async def cleanup_expired_frames(ctx: dict) -> int:
    """Окончательно удаляет кадры, удалённые больше 30 дней назад: сначала файлы в S3,
    потом строки в БД (раньше удалялись только строки, а файлы оставались навсегда)."""
    cutoff = datetime.now(timezone.utc) - timedelta(days=30)
    async with SessionLocal() as session:
        stmt = select(Frame).where(
            Frame.status == FrameStatus.DELETED,
            Frame.deleted_at < cutoff,
        )
        frames = list((await session.execute(stmt)).scalars().all())
        keys = [k for f in frames for k in _frame_keys(f)]
        if keys:
            await asyncio.to_thread(s3_client.delete_keys, keys)
        for f in frames:
            await session.delete(f)
        await session.commit()
    if frames:
        logger.info("cleanup_expired_done", count=len(frames))
    return len(frames)
