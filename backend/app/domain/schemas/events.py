from datetime import datetime, timedelta, timezone
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator

from app.domain.models.enums import (
    EventStatus,
    EventType,
    LutPreset,
    PhotoFormat,
    Plan,
    RevealMode,
)


class EventSettingsOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    frames_per_guest: int
    max_guests: int
    reveal_mode: RevealMode
    reveal_at: datetime | None
    plan: Plan
    lut_preset: LutPreset
    sound_enabled: bool
    photo_format: PhotoFormat


class EventOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    short_code: str
    title: str
    start_at: datetime
    end_at: datetime
    event_type: EventType
    status: EventStatus
    cover_url: str | None
    created_at: datetime
    updated_at: datetime
    settings: EventSettingsOut


class EventCreateIn(BaseModel):
    # Accept both 'title' (REST) and 'name' (Flutter client)
    title: str | None = Field(default=None, min_length=1, max_length=80)
    name: str | None = Field(default=None, min_length=1, max_length=80)
    start_at: datetime | None = None
    end_at: datetime | None = None
    event_type: EventType = EventType.OTHER
    # Optional settings — set immediately on creation if provided
    frames_per_guest: int = Field(default=24, ge=1, le=100)
    reveal_mode: RevealMode = RevealMode.INSTANT
    film: LutPreset | None = None   # Flutter alias for lut_preset
    lut_preset: LutPreset | None = None
    plan: Plan = Plan.FREE
    photo_format: PhotoFormat = PhotoFormat.PORTRAIT_34

    @model_validator(mode="after")
    def _resolve(self) -> "EventCreateIn":
        # name → title fallback
        if self.title is None and self.name is not None:
            self.title = self.name
        if not self.title:
            raise ValueError("title (or name) is required")
        # default dates: start = now, end = start + 24 h
        now = datetime.now(timezone.utc)
        if self.start_at is None:
            self.start_at = now
        if self.end_at is None:
            self.end_at = self.start_at + timedelta(hours=24)
        if self.end_at <= self.start_at:
            raise ValueError("end_at must be after start_at")
        # film → lut_preset alias
        if self.lut_preset is None and self.film is not None:
            self.lut_preset = self.film
        return self


class EventSettingsUpdateIn(BaseModel):
    frames_per_guest: int | None = Field(default=None, ge=1, le=100)
    reveal_mode: RevealMode | None = None
    reveal_at: datetime | None = None
    plan: Plan | None = None
    lut_preset: LutPreset | None = None
    sound_enabled: bool | None = None
    photo_format: PhotoFormat | None = None

    @field_validator("frames_per_guest")
    @classmethod
    def _check_frames(cls, v: int | None) -> int | None:
        return v


class QRCodeOut(BaseModel):
    short_code: str
    short_url: str
    png_base64: str
