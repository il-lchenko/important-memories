from datetime import datetime
from typing import Literal
from uuid import UUID

from pydantic import BaseModel

from app.domain.models.enums import Plan


# YooKassa payment method type. None = гость выбирает на странице YooKassa.
# 'sbp' — Система Быстрых Платежей (0.4-0.7% комиссии, самый выгодный).
# 'bank_card' — банковская карта (2.8-3.5%).
# 'yoo_money' — кошелёк ЮMoney.
# 'sberbank' — SberPay.
PaymentMethod = Literal["sbp", "bank_card", "yoo_money", "sberbank"]


class CheckoutIn(BaseModel):
    plan: Plan
    payment_method: PaymentMethod | None = None


class CheckoutOut(BaseModel):
    payment_id: UUID
    yookassa_id: str
    confirmation_url: str
    amount_kopecks: int
    currency: str = "RUB"


# Storage extension periods and their prices (kopecks) — see business plan v3.2 section 10.
ExtendPeriod = Literal["3m", "6m", "1y"]


class ExtendIn(BaseModel):
    period: ExtendPeriod
    payment_method: PaymentMethod | None = None


class ExtendOut(BaseModel):
    payment_id: UUID
    yookassa_id: str
    confirmation_url: str
    amount_kopecks: int
    currency: str = "RUB"
    period: ExtendPeriod
    new_expires_at: datetime
    days_added: int


UpgradeKind = Literal["guests", "frames"]


class UpgradeIn(BaseModel):
    kind: UpgradeKind
    payment_method: PaymentMethod | None = None


class UpgradeOut(BaseModel):
    payment_id: UUID
    yookassa_id: str
    confirmation_url: str
    amount_kopecks: int
    currency: str = "RUB"
    kind: UpgradeKind
    new_plan: str | None = None       # only for kind="guests"
    new_max_guests: int | None = None
    new_frames_per_guest: int | None = None  # only for kind="frames"
