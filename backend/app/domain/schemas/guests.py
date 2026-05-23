from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field

from app.domain.schemas.events import EventSettingsOut


class EventPreviewOut(BaseModel):
    title: str
    frames_per_guest: int
    reveal_at: datetime | None
    lut_preset: str
    status: str = "active"


class GuestJoinIn(BaseModel):
    short_code: str = Field(min_length=4, max_length=16)
    name: str = Field(min_length=1, max_length=40)
    fingerprint: str = Field(min_length=4, max_length=128)


class GuestEventOut(BaseModel):
    id: UUID
    title: str
    status: str
    end_at: datetime
    settings: EventSettingsOut


class GuestSessionOut(BaseModel):
    model_config = ConfigDict(from_attributes=False)

    guest_id: UUID
    guest_token: str
    event: GuestEventOut
    frames_used: int
    frames_remaining: int
