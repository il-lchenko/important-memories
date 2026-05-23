from io import BytesIO
from uuid import UUID

from PIL import Image
from sqlalchemy import select

from app.core.db import SessionLocal
from app.core.logging import logger
from app.domain.models import Frame, FrameStatus
from app.domain.models.enums import PhotoFormat
from app.domain.models.models import EventSettings
from app.infra import s3_client

# Target thumbnail dimensions per format (w × h)
_THUMB_SIZES: dict[PhotoFormat, tuple[int, int]] = {
    PhotoFormat.PORTRAIT_34:  (400, 533),
    PhotoFormat.LANDSCAPE_43: (533, 400),
}
_THUMB_RATIOS: dict[PhotoFormat, float] = {
    PhotoFormat.PORTRAIT_34:  3 / 4,
    PhotoFormat.LANDSCAPE_43: 4 / 3,
}


def _thumbnail_key(s3_key: str) -> str:
    if "/frames/" in s3_key:
        base, _, name = s3_key.rpartition("/")
        base = base.replace("/frames", "/thumbs")
        stem = name.rsplit(".", 1)[0]
        return f"{base}/{stem}.jpg"
    return s3_key + ".thumb.jpg"


def _center_crop(img: Image.Image, ratio: float) -> Image.Image:
    """Return a center-cropped copy of img with the given w/h ratio."""
    w, h = img.size
    if w / h > ratio:
        new_w = int(h * ratio)
        x = (w - new_w) // 2
        return img.crop((x, 0, x + new_w, h))
    else:
        new_h = int(w / ratio)
        y = (h - new_h) // 2
        return img.crop((0, y, w, y + new_h))


async def make_thumbnail(ctx: dict, frame_id: str) -> None:
    frame_uuid = UUID(frame_id)
    async with SessionLocal() as session:
        frame = (
            await session.execute(select(Frame).where(Frame.id == frame_uuid))
        ).scalar_one_or_none()
        if frame is None or frame.status == FrameStatus.DELETED:
            logger.warning("thumbnail_skip", frame_id=frame_id, reason="missing_or_deleted")
            return

        settings = (
            await session.execute(
                select(EventSettings).where(EventSettings.event_id == frame.event_id)
            )
        ).scalar_one_or_none()
        photo_format = settings.photo_format if settings else PhotoFormat.PORTRAIT_34

        target_w, target_h = _THUMB_SIZES[photo_format]
        crop_ratio = _THUMB_RATIOS[photo_format]

        original = s3_client.download_bytes(frame.s3_key)
        with Image.open(BytesIO(original)) as img:
            img = img.convert("RGB")
            img = _center_crop(img, crop_ratio)
            img = img.resize((target_w, target_h), Image.Resampling.LANCZOS)
            buf = BytesIO()
            img.save(buf, format="JPEG", quality=85, optimize=True)
            thumb_bytes = buf.getvalue()

        thumb_key = _thumbnail_key(frame.s3_key)
        s3_client.upload_bytes(thumb_key, thumb_bytes, "image/jpeg")
        frame.thumbnail_url = thumb_key
        await session.commit()
        logger.info("thumbnail_created", frame_id=frame_id, fmt=photo_format, size=len(thumb_bytes))
