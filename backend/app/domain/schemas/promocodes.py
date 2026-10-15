from datetime import datetime
from typing import Literal
from uuid import UUID

from pydantic import BaseModel, Field

from app.domain.models.enums import (
    PromocodeAppliesTo,
    PromocodeDiscountType,
    PromocodeKind,
)


class ValidatePromocodeIn(BaseModel):
    code: str = Field(..., min_length=1, max_length=32)
    event_id: UUID | None = None
    kind: Literal["checkout", "extend", "upgrade"] = "checkout"
    # Опциональный «предполагаемый» план/период — для точной прикидки суммы до
    # создания платежа. Если не задан, backend оценивает по event.settings.plan.
    plan: str | None = None
    period: str | None = None
    upgrade_kind: Literal["guests", "frames"] | None = None


class ValidatePromocodeOut(BaseModel):
    valid: bool
    discount_kopecks: int = 0
    final_amount_kopecks: int | None = None
    original_amount_kopecks: int | None = None
    error: str | None = None


class PromocodeOut(BaseModel):
    id: UUID
    code: str
    kind: PromocodeKind
    discount_type: PromocodeDiscountType
    discount_value: int
    max_redemptions: int | None
    redemptions_count: int
    expires_at: datetime | None
    applies_to: PromocodeAppliesTo
    min_amount_kopecks: int
    single_use_per_user: bool
    owner_user_id: UUID | None
    created_at: datetime

    class Config:
        from_attributes = True


class PromocodeCreateIn(BaseModel):
    code: str = Field(..., min_length=3, max_length=32)
    kind: PromocodeKind = PromocodeKind.MANUAL
    discount_type: PromocodeDiscountType = PromocodeDiscountType.PERCENT
    discount_value: int = Field(..., gt=0)
    max_redemptions: int | None = None
    expires_at: datetime | None = None
    applies_to: PromocodeAppliesTo = PromocodeAppliesTo.ALL
    min_amount_kopecks: int = 0
    single_use_per_user: bool = True
    owner_user_email: str | None = None


class PromocodePatchIn(BaseModel):
    max_redemptions: int | None = None
    expires_at: datetime | None = None
    discount_value: int | None = None


class ReferralStatsOut(BaseModel):
    referral_code: str | None
    referrals_count: int
    total_earned_kopecks: int
    pending_promocodes_count: int


class PromocodeRedemptionOut(BaseModel):
    id: UUID
    user_id: UUID
    payment_id: UUID | None
    discount_applied_kopecks: int
    redeemed_at: datetime

    class Config:
        from_attributes = True


class AdminToggleOut(BaseModel):
    user_id: UUID
    is_admin: bool
