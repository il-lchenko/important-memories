import html as html_mod
from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, Field, field_validator


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
    content_type: str = Field(pattern=r"^image/(jpeg|png|webp)$")
    size_bytes: int = Field(gt=0, le=20 * 1024 * 1024)


class FramePresignOut(BaseModel):
    frame_id: UUID
    upload_url: str
    expires_in: int


class FrameRegisterIn(BaseModel):
    frame_id: UUID
    captured_at: datetime
    width: int = Field(gt=0, le=20000)
    height: int = Field(gt=0, le=20000)


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
    """Guest updates caption or voice metadata for their own frame."""

    caption: str | None = Field(default=None, max_length=120)
    voice_s3_key: str | None = Field(default=None, max_length=1024)
    voice_duration_ms: int | None = Field(default=None, ge=0, le=25_000)
    voice_peaks: list[float] | None = Field(default=None)
    clear_caption: bool = False
    clear_voice: bool = False

    @field_validator("caption")
    @classmethod
    def _sanitize(cls, v: str | None) -> str | None:
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


class FrameRotationIn(BaseModel):
    rotation: int = Field(...)

    @field_validator("rotation")
    @classmethod
    def _validate_rotation(cls, v: int) -> int:
        if v not in (0, 90, 180, 270):
            raise ValueError("Rotation must be one of 0, 90, 180, 270")
        return v
