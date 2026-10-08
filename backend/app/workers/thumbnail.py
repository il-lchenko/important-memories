from datetime import datetime, timezone
from io import BytesIO
from uuid import UUID

import numpy as np
from PIL import Image, ImageOps
from sqlalchemy import select

from app.core.db import SessionLocal
from app.core.logging import logger
from app.domain.models import Frame, FrameSource, FrameStatus
from app.domain.models.enums import LutPreset, PhotoFormat
from app.domain.models.models import EventSettings
from app.infra import s3_client

# HEIC support для gallery-uploads с iPhone. Регистрируется один раз при импорте
# worker'а. Если pillow-heif не установлен — падаем при попытке декодировать
# HEIC, но остальной worker (camera-фото) продолжает работать.
try:
    import pillow_heif
    pillow_heif.register_heif_opener()
    _HEIC_SUPPORT = True
except ImportError:
    _HEIC_SUPPORT = False


# Cap для gallery-uploads: 12 MP (12_000_000 пикселей). Больше — считаем абьюзом
# (мобилки редко дают >12 MP; профессиональная камера — DSLR — не через галерею).
_UPLOAD_MP_CAP = 12_000_000

# Target thumbnail dimensions per format (w × h).
# 800×1066 в WebP q=85 (~60-90 KB): визуально идентично JPEG q=90 при 2× меньше
# размере — критично для mobile 3G/4G где каждые 50 KB заметны.
_THUMB_SIZES: dict[PhotoFormat, tuple[int, int]] = {
    PhotoFormat.PORTRAIT_34:  (800, 1066),
    PhotoFormat.LANDSCAPE_43: (1066, 800),
}
_THUMB_RATIOS: dict[PhotoFormat, float] = {
    PhotoFormat.PORTRAIT_34:  3 / 4,
    PhotoFormat.LANDSCAPE_43: 4 / 3,
}
_THUMB_QUALITY = 85

# Film presets — same parameters as filmLut.ts / film_lut.dart (color pipeline only, no grain/halation).
# Смягчены ~40% от исходной «жёсткой» версии — фильм узнаваем, но не выкручен.
_FILM_PRESETS: dict[str, dict] = {
    "portra400": {
        "r": [(0, 0.05), (0.20, 0.22), (0.5, 0.55), (0.82, 0.86), (1, 0.98)],
        "g": [(0, 0.04), (0.20, 0.20), (0.5, 0.51), (0.82, 0.83), (1, 0.95)],
        "b": [(0, 0.05), (0.20, 0.19), (0.5, 0.48), (0.82, 0.82), (1, 0.93)],
        "saturation": 1.0, "fade": 0.06,
        "shadow_tint": (2, 1, -1), "highlight_tint": (8, 2, -1), "temperature": 2,
    },
    "fuji400h": {
        "r": [(0, 0.08), (0.25, 0.26), (0.5, 0.50), (0.78, 0.80), (1, 0.93)],
        "g": [(0, 0.05), (0.25, 0.23), (0.5, 0.51), (0.78, 0.83), (1, 0.97)],
        "b": [(0, 0.11), (0.25, 0.32), (0.5, 0.56), (0.78, 0.84), (1, 0.96)],
        "saturation": 0.90, "fade": 0.11,
        "shadow_tint": (3, -1, 5), "highlight_tint": (-2, 1, 3), "temperature": -3,
    },
    "cinestill": {
        "r": [(0, 0.04), (0.2, 0.20), (0.5, 0.50), (0.8, 0.86), (1, 0.98)],
        "g": [(0, 0.05), (0.2, 0.22), (0.5, 0.51), (0.8, 0.82), (1, 0.95)],
        "b": [(0, 0.14), (0.2, 0.32), (0.5, 0.57), (0.8, 0.78), (1, 0.90)],
        "saturation": 1.02, "fade": 0.11,
        "shadow_tint": (-8, -4, 12), "highlight_tint": (7, 3, -6), "temperature": -8,
    },
    "ilford": {
        "r": [(0, 0.05), (0.22, 0.20), (0.5, 0.52), (0.78, 0.87), (1, 0.97)],
        "g": [(0, 0.05), (0.22, 0.20), (0.5, 0.52), (0.78, 0.87), (1, 0.97)],
        "b": [(0, 0.05), (0.22, 0.20), (0.5, 0.52), (0.78, 0.87), (1, 0.97)],
        "saturation": 0.0, "fade": 0.07,
        "shadow_tint": (0, 0, 0), "highlight_tint": (0, 0, 0), "temperature": 0,
        "bw": True,
    },
}

_lut_cache: dict[str, tuple[np.ndarray, np.ndarray, np.ndarray]] = {}


def _build_lut(points: list[tuple[float, float]]) -> np.ndarray:
    """Build 256-entry 1D LUT from control points using smoothstep interpolation."""
    pts = sorted(points, key=lambda p: p[0])
    lut = np.zeros(256, dtype=np.float32)
    for i in range(256):
        x = i / 255.0
        j = 0
        while j < len(pts) - 1 and pts[j + 1][0] < x:
            j += 1
        if j >= len(pts) - 1:
            lut[i] = pts[-1][1]
            continue
        x0, y0 = pts[j]
        x1, y1 = pts[j + 1]
        t = (x - x0) / (x1 - x0)
        ts = t * t * (3 - 2 * t)  # smoothstep
        lut[i] = y0 + (y1 - y0) * ts
    return np.clip(lut * 255, 0, 255).astype(np.uint8)


def _get_luts(key: str) -> tuple[np.ndarray, np.ndarray, np.ndarray] | None:
    if key in _lut_cache:
        return _lut_cache[key]
    f = _FILM_PRESETS.get(key)
    if f is None:
        return None
    result = (_build_lut(f["r"]), _build_lut(f["g"]), _build_lut(f["b"]))
    _lut_cache[key] = result
    return result


def apply_film_filter(img: Image.Image, lut_preset: str) -> Image.Image:
    """Apply film colour pipeline to a PIL Image. Returns a new Image."""
    if lut_preset == "original" or lut_preset not in _FILM_PRESETS:
        return img

    f = _FILM_PRESETS[lut_preset]
    luts = _get_luts(lut_preset)
    if luts is None:
        return img

    r_lut, g_lut, b_lut = luts
    arr = np.array(img, dtype=np.float32)  # H×W×3

    bw = f.get("bw", False)
    if bw:
        # Greyscale via luminance then apply single curve
        lum = (arr[:, :, 0] * 0.299 + arr[:, :, 1] * 0.587 + arr[:, :, 2] * 0.114).astype(np.uint8)
        mapped = r_lut[lum].astype(np.float32)
        arr[:, :, 0] = mapped
        arr[:, :, 1] = mapped
        arr[:, :, 2] = mapped
    else:
        # Per-channel curves
        ri = arr[:, :, 0].astype(np.uint8)
        gi = arr[:, :, 1].astype(np.uint8)
        bi = arr[:, :, 2].astype(np.uint8)
        arr[:, :, 0] = r_lut[ri].astype(np.float32)
        arr[:, :, 1] = g_lut[gi].astype(np.float32)
        arr[:, :, 2] = b_lut[bi].astype(np.float32)

        # Fade (lift blacks)
        fade = f["fade"]
        if fade > 0:
            arr += (255 - arr) * (fade * 0.18)

        # Tone-split tint
        lum = (arr[:, :, 0] * 0.299 + arr[:, :, 1] * 0.587 + arr[:, :, 2] * 0.114) / 255.0
        shadow_w = ((1 - lum) ** 2)[:, :, np.newaxis]
        high_w = (lum ** 2)[:, :, np.newaxis]
        st = np.array(f["shadow_tint"], dtype=np.float32)
        ht = np.array(f["highlight_tint"], dtype=np.float32)
        arr += shadow_w * st + high_w * ht

        # Temperature
        temp = f["temperature"]
        if temp != 0:
            arr[:, :, 0] += temp * 0.15
            arr[:, :, 2] -= temp * 0.15

        # Saturation (luminance-preserving)
        sat = f["saturation"]
        if sat != 1.0:
            lum2 = arr[:, :, 0] * 0.299 + arr[:, :, 1] * 0.587 + arr[:, :, 2] * 0.114
            for c in range(3):
                arr[:, :, c] = lum2 + (arr[:, :, c] - lum2) * sat

    arr = np.clip(arr, 0, 255).astype(np.uint8)
    return Image.fromarray(arr, "RGB")


def _thumbnail_key(s3_key: str) -> str:
    if "/frames/" in s3_key:
        base, _, name = s3_key.rpartition("/")
        base = base.replace("/frames", "/thumbs")
        stem = name.rsplit(".", 1)[0]
        return f"{base}/{stem}.webp"
    return s3_key + ".thumb.webp"


def _preview_key(s3_key: str) -> str:
    """Preview key for gallery — WebP формат, размер 1280px."""
    if "/frames/" in s3_key:
        base, _, name = s3_key.rpartition("/")
        base = base.replace("/frames", "/previews")
        stem = name.rsplit(".", 1)[0]
        return f"{base}/{stem}.webp"
    return s3_key + ".preview.webp"


# Preview: max side 1280px (HD+), WebP q=85 (~150-250 KB). В 2-3× меньше JPEG
# при том же visual quality — критично для мобильного 3G/4G. Оригинал 4000px q=93
# остаётся в s3_key для скачивания в полном качестве.
_PREVIEW_MAX_SIDE = 1280
_PREVIEW_QUALITY = 85


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


async def make_thumbnail(ctx: dict, frame_id: str, force_lut: bool = False) -> None:
    """Генерирует thumb + preview из S3-оригинала.

    Для camera-фото (source=camera) фильтр уже применён клиентом до PUT в S3 —
    worker только режет thumb/preview.

    Для gallery-uploads (source=upload, force_lut=True) worker дополнительно:
    - декодирует HEIC → jpeg (через pillow-heif)
    - удаляет EXIF полностью (создаём новый Image без metadata)
    - проверяет 12 MP cap
    - применяет плёночный фильтр (LUT) на full-res
    - перезаписывает s3_key: filtered JPEG вместо raw (raw не храним)
    - если ключ был .heic — переименовывает в .jpg
    """
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
        lut_preset = settings.lut_preset if settings else LutPreset.PORTRA400

        target_w, target_h = _THUMB_SIZES[photo_format]
        crop_ratio = _THUMB_RATIOS[photo_format]

        # Для gallery-uploads принудительно применяем LUT на сервере — клиент
        # шлёт raw. Флаг также передаётся из register_frame по source=upload.
        is_upload = frame.source == FrameSource.UPLOAD or force_lut

        try:
            original = s3_client.download_bytes(frame.s3_key)
            with Image.open(BytesIO(original)) as raw:
                raw = ImageOps.exif_transpose(raw)

                if is_upload:
                    # 12 MP cap — защита от абьюза (профессиональные фото 24MP+).
                    w0, h0 = raw.size
                    if w0 * h0 > _UPLOAD_MP_CAP:
                        logger.warning(
                            "upload_mp_cap_exceeded",
                            frame_id=frame_id, width=w0, height=h0,
                        )
                        frame.status = FrameStatus.DELETED
                        frame.deleted_at = datetime.now(timezone.utc)
                        try:
                            s3_client.delete_object(frame.s3_key)
                        except Exception:
                            pass
                        await session.commit()
                        return
                    # Полностью убираем EXIF: создаём новую картинку и paste'им пиксели.
                    # ImageOps.exif_transpose уже применил ориентацию — теперь исходные
                    # метаданные больше не нужны и потенциально приватны (GPS).
                    clean = Image.new("RGB", raw.size)
                    clean.paste(raw)
                    raw = clean
                else:
                    raw = raw.convert("RGB")

                # Для uploads: применяем LUT на full-res, потом перезаписываем s3_key
                # фильтрованной версией. Так zip_builder и public share получают
                # уже обработанный кадр (raw не сохраняется).
                if is_upload:
                    filtered = apply_film_filter(raw, lut_preset.value)
                    fbuf = BytesIO()
                    filtered.save(fbuf, format="JPEG", quality=_PREVIEW_QUALITY, optimize=True)
                    filtered_bytes = fbuf.getvalue()
                    # Если ключ .heic — переименовываем в .jpg (клиент/архив ожидает jpeg).
                    new_key = frame.s3_key
                    if new_key.rsplit(".", 1)[-1].lower() in ("heic", "heif", "png", "webp"):
                        old_key = new_key
                        new_key = new_key.rsplit(".", 1)[0] + ".jpg"
                        s3_client.upload_bytes(new_key, filtered_bytes, "image/jpeg")
                        try:
                            s3_client.delete_object(old_key)
                        except Exception:
                            pass
                        frame.s3_key = new_key
                    else:
                        s3_client.upload_bytes(new_key, filtered_bytes, "image/jpeg")
                    # Работаем дальше с filtered для thumb/preview.
                    raw = filtered

                # Плёночный фильтр применяет КЛИЕНТ (Flutter guest-camera / PWA useCamera)
                # ДО загрузки на S3. Повторно применять здесь нельзя — это удваивает
                # эффект (тени становятся ярко-синими на cinestill, контраст ломается).
                # Thumbnail 400×533 (or 533×400) for fast gallery scroll.
                thumb_img = _center_crop(raw, crop_ratio)
                thumb_img = thumb_img.resize((target_w, target_h), Image.Resampling.LANCZOS)
                tbuf = BytesIO()
                thumb_img.save(tbuf, format="WEBP", quality=_THUMB_QUALITY, method=4)
                thumb_bytes = tbuf.getvalue()

                # Preview 1600px on the longer side — used in fullscreen album view.
                # Keeps aspect ratio (no center-crop) so aspect matches original.
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
                pbuf = BytesIO()
                preview_img.save(pbuf, format="WEBP", quality=_PREVIEW_QUALITY, method=4)
                preview_bytes = pbuf.getvalue()

            thumb_key = _thumbnail_key(frame.s3_key)
            preview_key = _preview_key(frame.s3_key)
            s3_client.upload_bytes(thumb_key, thumb_bytes, "image/webp")
            s3_client.upload_bytes(preview_key, preview_bytes, "image/webp")
            frame.thumbnail_url = thumb_key
            frame.preview_url = preview_key
            frame.status = FrameStatus.UPLOADED
            await session.commit()
            logger.info(
                "thumbnail_and_preview_created",
                frame_id=frame_id,
                fmt=photo_format,
                lut=lut_preset,
                source=frame.source.value,
                thumb_size=len(thumb_bytes),
                preview_size=len(preview_bytes),
            )
        except Exception as exc:
            logger.error("thumbnail_failed", frame_id=frame_id, error=str(exc), exc_info=True)
