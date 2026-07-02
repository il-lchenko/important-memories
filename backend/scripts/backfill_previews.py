"""One-shot backfill: generate preview_url (1600px q=88) for all Frames where it's null.

Usage:
    docker exec im-backend uv run python -m scripts.backfill_previews

Idempotent: only processes Frame rows where preview_url IS NULL and status = UPLOADED.
Existing thumbnails and originals are not touched — only new preview files are added.
"""
import asyncio
from io import BytesIO

from PIL import Image
from sqlalchemy import select

from app.core.db import SessionLocal
from app.core.logging import logger
from app.domain.models import Frame, FrameStatus
from app.domain.models.enums import LutPreset
from app.domain.models.models import EventSettings
from app.infra import s3_client
from app.workers.thumbnail import (
    _PREVIEW_MAX_SIDE,
    _PREVIEW_QUALITY,
    _preview_key,
    apply_film_filter,
)


async def process_frame(session, frame: Frame) -> bool:
    """Generate & upload preview for a single frame. Returns True on success."""
    try:
        settings_row = (
            await session.execute(
                select(EventSettings).where(EventSettings.event_id == frame.event_id)
            )
        ).scalar_one_or_none()
        lut_preset = settings_row.lut_preset if settings_row else LutPreset.PORTRA400

        original = s3_client.download_bytes(frame.s3_key)
        with Image.open(BytesIO(original)) as raw:
            raw = raw.convert("RGB")
            pw, ph = raw.size
            longer = max(pw, ph)
            if longer > _PREVIEW_MAX_SIDE:
                scale = _PREVIEW_MAX_SIDE / longer
                preview_img = raw.resize(
                    (round(pw * scale), round(ph * scale)),
                    Image.Resampling.LANCZOS,
                )
            else:
                preview_img = raw.copy()
            preview_img = apply_film_filter(preview_img, str(lut_preset))
            buf = BytesIO()
            preview_img.save(buf, format="JPEG", quality=_PREVIEW_QUALITY, optimize=True)
            preview_bytes = buf.getvalue()

        preview_key = _preview_key(frame.s3_key)
        s3_client.upload_bytes(preview_key, preview_bytes, "image/jpeg")
        frame.preview_url = preview_key
        await session.commit()
        logger.info(
            "backfill_preview_ok",
            frame_id=str(frame.id),
            preview_size=len(preview_bytes),
        )
        return True
    except Exception as exc:
        logger.warning("backfill_preview_fail", frame_id=str(frame.id), error=str(exc))
        await session.rollback()
        return False


async def main() -> None:
    async with SessionLocal() as session:
        stmt = (
            select(Frame)
            .where(Frame.preview_url.is_(None))
            .where(Frame.status == FrameStatus.UPLOADED)
            .order_by(Frame.captured_at)
        )
        frames = list((await session.execute(stmt)).scalars().all())

    print(f"Найдено {len(frames)} кадров без preview_url. Начинаю backfill…")

    ok = 0
    fail = 0
    for i, frame in enumerate(frames, start=1):
        async with SessionLocal() as s:
            fresh = (
                await s.execute(select(Frame).where(Frame.id == frame.id))
            ).scalar_one_or_none()
            if fresh is None or fresh.preview_url is not None:
                continue
            success = await process_frame(s, fresh)
            if success:
                ok += 1
            else:
                fail += 1
        if i % 20 == 0:
            print(f"  … {i}/{len(frames)} (ok={ok}, fail={fail})")

    print(f"\nГотово. ok={ok}, fail={fail}, всего={len(frames)}")


if __name__ == "__main__":
    asyncio.run(main())
