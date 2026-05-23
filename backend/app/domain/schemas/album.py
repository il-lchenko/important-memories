from datetime import datetime
from uuid import UUID

from pydantic import BaseModel


class AlbumFrameOut(BaseModel):
    id: UUID
    guest_id: UUID
    guest_name: str
    captured_at: datetime
    thumbnail_url: str | None
    full_url: str
    width: int
    height: int
    is_mine: bool = False


class AlbumOut(BaseModel):
    items: list[AlbumFrameOut]
    next_cursor: str | None
    revealed: bool
    total_frames: int
