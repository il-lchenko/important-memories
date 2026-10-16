from typing import Literal

from pydantic import BaseModel


class EntitlementFeaturesOut(BaseModel):
    solo_album: bool
    mini_albums: bool
    # Дополнительные QR-стили и шрифты названия (доступны с «Плюс» после запуска подписки).
    extra_styles: bool = True


class EntitlementsOut(BaseModel):
    tier: Literal["free", "subscription", "admin"]
    is_admin: bool
    subscription_enabled: bool
    # Подписка «Плюс» действует прямо сейчас (админ считается подписчиком).
    plus: bool = False
    free_events_per_month: int | None
    free_events_used: int
    free_events_left: int | None
    # Сколько бесплатных альбомов живёт одновременно (удаление освобождает место).
    free_active_limit: int | None = None
    free_active_used: int = 0
    free_active_left: int | None = None
    # Соло-альбомы: кадры за календарный месяц и места в хранилище.
    solo_frames_per_month: int = 0
    solo_frames_used: int = 0
    solo_frames_left: int = 0
    solo_stored_limit: int = 0
    solo_stored_used: int = 0
    solo_retention_days: int = 30
    # Мини-альбомы: None — без лимита по числу.
    mini_albums_limit: int | None = None
    mini_frames_per_album: int = 0
    features: EntitlementFeaturesOut
