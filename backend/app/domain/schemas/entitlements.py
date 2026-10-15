from typing import Literal

from pydantic import BaseModel


class EntitlementFeaturesOut(BaseModel):
    solo_album: bool
    mini_albums: bool


class EntitlementsOut(BaseModel):
    tier: Literal["free", "subscription", "admin"]
    is_admin: bool
    subscription_enabled: bool
    free_events_per_month: int | None
    free_events_used: int
    free_events_left: int | None
    features: EntitlementFeaturesOut
