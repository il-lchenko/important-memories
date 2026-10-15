from datetime import datetime
from uuid import UUID

from pydantic import BaseModel


class AlbumFrameOut(BaseModel):
    id: UUID
    guest_id: UUID | None
    guest_name: str
    guest_avatar_url: str | None = None
    captured_at: datetime
    thumbnail_url: str | None
    preview_url: str | None
    full_url: str
    width: int
    height: int
    is_mine: bool = False
    caption: str | None = None
    voice_url: str | None = None
    voice_duration_ms: int | None = None
    voice_peaks: list[float] | None = None
    rotation: int = 0
    # Длинная заметка/мысль к кадру (до 2000 символов). Отдельно от caption.
    note: str | None = None
    # camera vs upload — используется клиентом для метки-скрепки на карточке.
    source: str = "camera"


class AlbumOut(BaseModel):
    items: list[AlbumFrameOut]
    next_cursor: str | None
    revealed: bool
    total_frames: int
    is_admin_preview: bool = False
    title_font: str | None = None


class PublicAlbumMetaOut(BaseModel):
    id: UUID
    title: str
    status: str
    cover_url: str | None
    total_frames: int
    revealed: bool
    title_font: str | None = None
