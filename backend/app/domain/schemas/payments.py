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
    promocode: str | None = None


class CheckoutOut(BaseModel):
    payment_id: UUID
    yookassa_id: str
    confirmation_url: str
    amount_kopecks: int
    currency: str = "RUB"
    original_amount_kopecks: int | None = None
    discount_kopecks: int = 0
    admin_bypass: bool = False


# Storage extension periods and their prices (kopecks) — see business plan v3.2 section 10.
ExtendPeriod = Literal["3m", "6m", "1y"]


class ExtendIn(BaseModel):
    period: ExtendPeriod
    payment_method: PaymentMethod | None = None
    promocode: str | None = None


class ExtendOut(BaseModel):
    payment_id: UUID
    yookassa_id: str
    confirmation_url: str
    amount_kopecks: int
    currency: str = "RUB"
    period: ExtendPeriod
    new_expires_at: datetime
    days_added: int
    original_amount_kopecks: int | None = None
    discount_kopecks: int = 0
    admin_bypass: bool = False


UpgradeKind = Literal["guests", "frames"]


class UpgradeIn(BaseModel):
    kind: UpgradeKind
    payment_method: PaymentMethod | None = None
    promocode: str | None = None


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
    original_amount_kopecks: int | None = None
    discount_kopecks: int = 0
    admin_bypass: bool = False


class PricingTierOut(BaseModel):
    plan: Plan
    max_guests: int
    price_kopecks: int
    retention_days: int


class PricingCustomOut(BaseModel):
    from_guests: int
    max_guests: int
    base_price_kopecks: int
    per_guest_kopecks: int
    retention_days: int


class PricingFramesOut(BaseModel):
    base_per_guest: int
    extended_per_guest: int
    price_per_guest_kopecks: int


class PricingExtendOut(BaseModel):
    period: ExtendPeriod
    days: int
    # Минимальная цена продления. Итог = max(price_kopecks, per_guest_kopecks × max_guests).
    price_kopecks: int
    per_guest_kopecks: int = 0


class PricingPlusOut(BaseModel):
    """Подписка «Плюс»: цены и включена ли продажа."""
    enabled: bool
    month_kopecks: int
    year_kopecks: int
    # Что даёт подписка в сравнении с бесплатным тарифом.
    solo_frames_per_month: int = 0
    solo_free_frames_per_month: int = 0
    solo_retention_days: int = 0
    events_active: int = 0
    events_per_month: int = 0
    free_events_active: int = 0
    free_events_per_month: int = 0
    mini_frames_per_album: int = 0
    mini_free_albums: int = 0
    mini_free_frames_per_album: int = 0


class PricingOut(BaseModel):
    currency: str = "RUB"
    tiers: list[PricingTierOut]
    custom: PricingCustomOut
    frames: PricingFramesOut
    extend: list[PricingExtendOut]
    # Продление хранения соло-альбома (цена не зависит от числа гостей).
    solo_extend: list[PricingExtendOut] = []
    plus: PricingPlusOut | None = None
    upgrade_premium: float
    # Бесплатный тариф: сколько альбомов может жить одновременно и сколько
    # бесплатных активаций в месяц. None — без лимита.
    free_active_events: int | None = None
    free_events_per_month: int | None = None
