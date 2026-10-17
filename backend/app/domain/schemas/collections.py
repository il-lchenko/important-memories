import html as html_mod
from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, Field, field_validator


class CollectionCreateIn(BaseModel):
    title: str = Field(min_length=1, max_length=80)

    @field_validator("title")
    @classmethod
    def _sanitize(cls, v: str) -> str:
        clean = html_mod.escape(v.strip(), quote=True)
        if not clean:
            raise ValueError("Название не может быть пустым")
        return clean


class CollectionCoverFromFrameIn(BaseModel):
    frame_id: UUID


class CollectionItemsIn(BaseModel):
    frame_ids: list[UUID] = Field(min_length=1, max_length=100)


class CollectionFrameOut(BaseModel):
    id: UUID
    event_id: UUID
    event_title: str
    captured_at: datetime
    thumbnail_url: str | None
    preview_url: str | None
    full_url: str
    width: int
    height: int
    rotation: int = 0
    caption: str | None = None
    # Кадр снят самим пользователем (а не другим гостем альбома).
    is_mine: bool = False


class CollectionSummaryOut(BaseModel):
    id: UUID
    title: str
    items_count: int
    created_at: datetime
    preview_urls: list[str] = []
    cover_url: str | None = None


class CollectionOut(BaseModel):
    id: UUID
    title: str
    created_at: datetime
    items: list[CollectionFrameOut]
    frames_limit: int
    cover_url: str | None = None
    # Сколько кадров в подборке недоступно (автор удалил, срок хранения истёк, нет доступа).
    unavailable_count: int = 0


class CollectionsListOut(BaseModel):
    collections: list[CollectionSummaryOut]
    albums_limit: int | None
    frames_per_album: int
