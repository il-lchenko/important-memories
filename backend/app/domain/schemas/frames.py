import html as html_mod
from datetime import datetime
from typing import Literal
from uuid import UUID

from pydantic import BaseModel, Field, field_validator, model_validator


def _sanitize_caption(v: str | None) -> str | None:
    """Escape HTML in user text to prevent XSS. Preserves display chars."""
    if v is None:
        return None
    stripped = v.strip()
    if not stripped:
        return None
    # Escape < > & " ' — safe for display in both PWA and Flutter.
    return html_mod.escape(stripped, quote=True)


class FramePresignIn(BaseModel):
    # Для camera-фото: jpeg/png/webp. Для gallery-uploads добавляется heic/heif —
    # worker сконвертирует в jpeg при обработке.
    content_type: str = Field(pattern=r"^image/(jpeg|png|webp|heic|heif)$")
    size_bytes: int = Field(gt=0, le=20 * 1024 * 1024)
    source: Literal["camera", "upload"] = "camera"
    # SHA-256 файла — только для source=upload (дедуп).
    upload_hash: str | None = Field(default=None, pattern=r"^[a-f0-9]{64}$")
    # Повторная попытка загрузки того же кадра (обрыв сети, истёк URL): сервер выдаёт
    # новый URL для уже созданного PENDING-кадра, не занимая ещё одно место в квоте.
    resume_frame_id: UUID | None = None

    @model_validator(mode="after")
    def _check_source_rules(self) -> "FramePresignIn":
        if self.source == "upload":
            # Uploads должны иметь hash — иначе не сработает дедуп
            if self.upload_hash is None:
                raise ValueError("upload_hash is required for source=upload")
            # Uploads имеют более жёсткий лимит размера (12 MB, а не 20)
            if self.size_bytes > 12 * 1024 * 1024:
                raise ValueError("Uploads limited to 12 MB")
        else:
            # Camera-фото не должны присылать hash — упрощает БД (NULL для camera)
            if self.upload_hash is not None:
                raise ValueError("upload_hash is only for source=upload")
            # Camera-фото не могут быть HEIC (браузер/камера уже дают JPEG)
            if self.content_type in ("image/heic", "image/heif"):
                raise ValueError("HEIC content_type is only for source=upload")
        return self


class FramePresignOut(BaseModel):
    frame_id: UUID
    upload_url: str
    expires_in: int
    # True если файл уже загружен ранее (тот же upload_hash в этом событии).
    # Клиент в этом случае может пропустить PUT — frame_id указывает на существующий кадр.
    deduplicated: bool = False


class FrameRegisterIn(BaseModel):
    frame_id: UUID
    captured_at: datetime
    width: int = Field(gt=0, le=20000)
    height: int = Field(gt=0, le=20000)
    source: Literal["camera", "upload"] = "camera"


class FrameRegisterOut(BaseModel):
    id: UUID
    status: str
    frames_remaining: int


class FrameVoicePresignIn(BaseModel):
    size_bytes: int = Field(gt=0, le=2 * 1024 * 1024)
    content_type: str = Field(default="audio/webm", pattern=r"^audio/(webm|ogg|mp4|wav|wave|mpeg)$")


class FrameVoicePresignOut(BaseModel):
    voice_s3_key: str
    upload_url: str
    expires_in: int


class FrameUpdateIn(BaseModel):
    """Guest updates caption, voice, note or rotation for their own frame."""

    caption: str | None = Field(default=None, max_length=120)
    note: str | None = Field(default=None, max_length=2000)
    voice_s3_key: str | None = Field(default=None, max_length=1024)
    voice_duration_ms: int | None = Field(default=None, ge=0, le=25_000)
    voice_peaks: list[float] | None = Field(default=None)
    rotation: int | None = Field(default=None)
    clear_caption: bool = False
    clear_voice: bool = False
    clear_note: bool = False

    @field_validator("caption")
    @classmethod
    def _sanitize(cls, v: str | None) -> str | None:
        return _sanitize_caption(v)

    @field_validator("note")
    @classmethod
    def _sanitize_note(cls, v: str | None) -> str | None:
        return _sanitize_caption(v)

    @field_validator("voice_peaks")
    @classmethod
    def _validate_peaks(cls, v: list[float] | None) -> list[float] | None:
        if v is None:
            return v
        if len(v) > 100:
            raise ValueError("Too many peaks (max 100)")
        for p in v:
            if p < 0 or p > 1:
                raise ValueError("Peak values must be in [0, 1]")
        return v

    @field_validator("rotation")
    @classmethod
    def _validate_rotation(cls, v: int | None) -> int | None:
        if v is None:
            return v
        if v not in (0, 90, 180, 270):
            raise ValueError("Rotation must be one of 0, 90, 180, 270")
        return v


class FrameRotationIn(BaseModel):
    rotation: int = Field(...)

    @field_validator("rotation")
    @classmethod
    def _validate_rotation(cls, v: int) -> int:
        if v not in (0, 90, 180, 270):
            raise ValueError("Rotation must be one of 0, 90, 180, 270")
        return v
