from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, Field


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
