import html as html_mod
from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, field_validator

from app.domain.schemas.events import EventSettingsOut


def _sanitize_name(v: str | None) -> str | None:
    """Escape HTML in user-supplied names to prevent XSS in album views."""
    if v is None:
        return None
    stripped = v.strip()
    if not stripped:
        return None
    return html_mod.escape(stripped, quote=True)


class EventPreviewOut(BaseModel):
    title: str
    frames_per_guest: int
    reveal_at: datetime | None
    start_at: datetime | None = None
    lut_preset: str
    status: str = "active"
    cover_url: str | None = None


class GuestJoinIn(BaseModel):
    short_code: str = Field(min_length=4, max_length=16)
    # Если запрос с Bearer и юзер уже подключён к событию — name можно не передавать
    # (будет использован existing.name). Для нового invited гостя — fallback на user.display_name.
    # Для анонимного гостя — обязательно.
    name: str | None = Field(default=None, max_length=40)
    fingerprint: str = Field(min_length=4, max_length=128)

    @field_validator("name")
    @classmethod
    def _sanitize(cls, v: str | None) -> str | None:
        return _sanitize_name(v)


class GuestNameUpdateIn(BaseModel):
    name: str = Field(min_length=1, max_length=40)

    @field_validator("name")
    @classmethod
    def _sanitize(cls, v: str) -> str:
        clean = _sanitize_name(v)
        if not clean:
            raise ValueError("Имя не может быть пустым")
        return clean


class InvitedEventOut(BaseModel):
    id: UUID
    short_code: str
    title: str
    status: str
    start_at: datetime | None = None
    end_at: datetime
    cover_url: str | None = None
    my_frames_count: int
    total_frames: int


class GuestEventOut(BaseModel):
    id: UUID
    title: str
    status: str
    start_at: datetime | None = None
    end_at: datetime
    settings: EventSettingsOut


class GuestSessionOut(BaseModel):
    model_config = ConfigDict(from_attributes=False)

    guest_id: UUID
    guest_token: str
    name: str
    event: GuestEventOut
    frames_used: int
    frames_remaining: int
