"""Schemas for the "Кадры" (Memories) feed."""
from datetime import datetime
from typing import Literal
from uuid import UUID

from pydantic import BaseModel


MemoryBlockType = Literal[
    "tilted",       # 4 наклонённые карточки
    "collage_a",    # 1 большое слева + 2 маленьких справа
    "collage_b",    # 2×2 равных
    "collage_c",    # 2 сверху + 1 широкое снизу
    "collage_d",    # центр-акцент
    "collage_e",    # 1 крупное + 3 стек справа
    "grid_6",       # 3×2 карусель
]

MemoryBlockKind = Literal["single", "collection"]


class MemoryThumb(BaseModel):
    """Одно фото в блоке. Тап открывает его в оригинальном альбоме."""
    url: str
    event_id: UUID
    frame_id: UUID


class MemoryBlock(BaseModel):
    type: MemoryBlockType
    kind: MemoryBlockKind
    title: str
    # single: date_iso — captured_at или created_at альбома
    # collection: albums_count — сколько альбомов в сборке
    date_iso: datetime | None = None
    albums_count: int | None = None
    # single → event_id обязателен (для tap → open album)
    event_id: UUID | None = None
    # collection → event_ids для «вижу все альбомы этой темы»
    event_ids: list[UUID] = []
    # event_type — для отрисовки амбер-бейджа над названием (только single).
    # Для collection же тип уже виден в самом title, бейдж не нужен.
    event_type: str | None = None
    thumbs: list[MemoryThumb]


class MemoriesOut(BaseModel):
    blocks: list[MemoryBlock]
