from datetime import datetime
from typing import Literal
from uuid import UUID

from pydantic import BaseModel

SubscriptionPeriod = Literal["month", "year"]


class SubscriptionOut(BaseModel):
    # Продажа включена (SUBSCRIPTION_ENABLED).
    enabled: bool
    # Подписка «Плюс» действует прямо сейчас.
    plus: bool
    status: str | None = None
    period: str | None = None
    current_period_end: datetime | None = None
    cancel_at_period_end: bool = False
    month_kopecks: int
    year_kopecks: int


class SubscriptionCheckoutIn(BaseModel):
    period: SubscriptionPeriod = "month"
    payment_method: Literal["sbp", "bank_card", "yoo_money", "sberbank"] | None = None


class SubscriptionCheckoutOut(BaseModel):
    payment_id: UUID
    confirmation_url: str
    amount_kopecks: int
    currency: str = "RUB"
