import zipfile
from io import BytesIO
from uuid import UUID

from sqlalchemy import select

from app.core.config import settings
from app.core.db import SessionLocal
from app.core.logging import logger
from app.domain.models import Frame, FrameStatus, Guest
from app.infra import s3_client


def _safe_name(name: str) -> str:
    keep = [c if c.isalnum() or c in " _-" else "_" for c in name]
    return "".join(keep).strip() or "guest"


async def build_zip(ctx: dict, event_id: str, job_id: str) -> dict:
    event_uuid = UUID(event_id)
    async with SessionLocal() as session:
        stmt = (
            select(Frame, Guest.name)
            .join(Guest, Guest.id == Frame.guest_id)
            .where(
                Frame.event_id == event_uuid,
                Frame.status == FrameStatus.UPLOADED,
            )
            .order_by(Frame.captured_at)
        )
        rows = list((await session.execute(stmt)).all())

    if not rows:
        logger.info("zip_empty", event_id=event_id, job_id=job_id)
        return {"status": "empty", "frame_count": 0}

    buf = BytesIO()
    with zipfile.ZipFile(buf, "w", zipfile.ZIP_STORED) as zf:
        seen: dict[str, int] = {}
        for frame, guest_name in rows:
            try:
                body = s3_client.download_bytes(frame.s3_key)
            except Exception as exc:
                logger.warning("zip_skip_frame", frame_id=str(frame.id), error=str(exc))
                continue
            ext = frame.s3_key.rsplit(".", 1)[-1].lower() if "." in frame.s3_key else "jpg"
            stem = _safe_name(guest_name)
            seen[stem] = seen.get(stem, 0) + 1
            name = f"{stem}_{seen[stem]:03d}.{ext}"
            zf.writestr(name, body)

    zip_key = f"events/{event_id}/archives/{job_id}.zip"
    s3_client.upload_bytes(zip_key, buf.getvalue(), "application/zip")
    download_url = s3_client.presign_get(zip_key, expires_in=7 * 24 * 3600)
    logger.info(
        "zip_ready",
        event_id=event_id,
        job_id=job_id,
        frame_count=len(rows),
        bytes=len(buf.getvalue()),
    )
    return {
        "status": "ready",
        "frame_count": len(rows),
        "download_url": download_url,
    }
