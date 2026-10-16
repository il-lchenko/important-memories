from datetime import datetime, timedelta, timezone
from uuid import UUID, uuid4

from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.core.errors import (
    ConflictError,
    NotFoundError,
    PermissionDeniedError,
)
from app.core.logging import logger
from app.domain.models import EventStatus, Payment, PaymentStatus, Plan
from app.domain.schemas.payments import (
    CheckoutOut,
    ExtendOut,
    ExtendPeriod,
    PricingCustomOut,
    PricingExtendOut,
    PricingFramesOut,
    PricingPlusOut,
    PricingOut,
    PricingTierOut,
    UpgradeKind,
    UpgradeOut,
)
from app.infra import yookassa_client
from app.repos import event_repo, payment_repo, user_repo
from app.services import entitlement_service, promocode_service, subscription_service

PLAN_PRICES_KOPECKS: dict[Plan, int] = {
    # Business plan v3.2 pricing grid. All values in kopecks.
    Plan.FREE: 0,
    Plan.P10: 24900,     # 249 ₽
    Plan.P25: 44900,     # 449 ₽
    Plan.P50: 129000,    # 1 290 ₽
    Plan.P75: 199000,    # 1 990 ₽
    Plan.P100: 299000,   # 2 990 ₽
    Plan.P150: 449000,   # 4 490 ₽
    Plan.P175: 549000,   # 5 490 ₽
    Plan.P200: 629000,   # 6 290 ₽
    Plan.P250: 769000,   # 7 690 ₽
    # CUSTOM (>250): computed via price_for_guests(n) in event_service.
    Plan.UNLIMITED: 769000,  # legacy — treat as P250
}

PAID_TIERS: tuple[Plan, ...] = (
    Plan.P10, Plan.P25, Plan.P50, Plan.P75, Plan.P100,
    Plan.P150, Plan.P175, Plan.P200, Plan.P250,
)

def pricing_v2_active(now: datetime | None = None) -> bool:
    """Новые цены действуют для покупок с PRICING_V2_FROM (уведомление по оферте — 14 дней)."""
    now = now or datetime.now(timezone.utc)
    return now >= datetime.fromisoformat(settings.PRICING_V2_FROM)


# 250+ гостей: цена P250 + N ₽ за каждого гостя сверх 250, до 2000 гостей.
# v2: 35 ₽ — при 30 ₽ хранение 1000+ гостей в худшем случае почти не окупалось.
_CUSTOM_PER_GUEST_KOPECKS_V1 = 3000
_CUSTOM_PER_GUEST_KOPECKS_V2 = 3500
CUSTOM_MAX_GUESTS = 2000


def custom_per_guest_kopecks() -> int:
    return _CUSTOM_PER_GUEST_KOPECKS_V2 if pricing_v2_active() else _CUSTOM_PER_GUEST_KOPECKS_V1


# Продление хранения: (дней, минимальная цена в копейках).
EXTEND_OPTIONS: dict[str, tuple[int, int]] = {
    "3m": (90, 49000),    # от 490 ₽
    "6m": (180, 79000),   # от 790 ₽
    "1y": (365, 129000),  # от 1 290 ₽
}
# v2: продление растёт с размером альбома — фиксированные 490 ₽ за 3 месяца
# не покрывали хранение альбомов от 75 гостей.
EXTEND_PER_GUEST_KOPECKS: dict[str, int] = {
    "3m": 1000,   # 10 ₽ за гостя
    "6m": 1700,   # 17 ₽ за гостя
    "1y": 3200,   # 32 ₽ за гостя
}


# Продление соло-альбома: фиксированные цены (до 150 кадров на альбом в месяц).
SOLO_EXTEND_OPTIONS: dict[str, tuple[int, int]] = {
    "3m": (90, 9900),     # 99 ₽
    "6m": (180, 17900),   # 179 ₽
    "1y": (365, 29900),   # 299 ₽
}


def extend_price_kopecks(period: str, max_guests: int) -> int:
    _days, minimum = EXTEND_OPTIONS[period]
    if not pricing_v2_active():
        return minimum
    return max(minimum, EXTEND_PER_GUEST_KOPECKS[period] * max_guests)

# Guest count upgrade path (from -> to). Only "next tier" upgrades are supported.
# Aligned with business plan v3.2 discrete tiers.
_UPGRADE_GUESTS_PATH: dict[Plan, Plan] = {
    Plan.FREE: Plan.P10,
    Plan.P10: Plan.P25,
    Plan.P25: Plan.P50,
    Plan.P50: Plan.P75,
    Plan.P75: Plan.P100,
    Plan.P100: Plan.P150,
    Plan.P150: Plan.P175,
    Plan.P175: Plan.P200,
    Plan.P200: Plan.P250,
    # P250 → CUSTOM handled separately (custom_guests param)
}

# Post-purchase upgrade premium (business plan v3.2 section 10 — "no arbitrage" rule).
_UPGRADE_PREMIUM = 1.15

# Extended frames per guest (default 30, extension 45).
# v2: 10 ₽/гость — при 5 ₽ лишние кадры на долгих тарифах хранились в убыток.
_FRAMES_EXTENDED = 45
_FRAMES_DEFAULT = 30
_FRAMES_UPGRADE_PRICE_V1_KOPECKS = 500
_FRAMES_UPGRADE_PRICE_V2_KOPECKS = 1000


def frames_upgrade_price_per_guest_kopecks() -> int:
    return _FRAMES_UPGRADE_PRICE_V2_KOPECKS if pricing_v2_active() else _FRAMES_UPGRADE_PRICE_V1_KOPECKS


def pricing_catalog() -> PricingOut:
    from app.services.event_service import _PLAN_LIMITS, retention_days

    top = PAID_TIERS[-1]
    return PricingOut(
        tiers=[
            PricingTierOut(
                plan=plan,
                max_guests=_PLAN_LIMITS[plan],
                price_kopecks=PLAN_PRICES_KOPECKS[plan],
                retention_days=retention_days(plan),
            )
            for plan in (Plan.FREE, *PAID_TIERS)
        ],
        custom=PricingCustomOut(
            from_guests=_PLAN_LIMITS[top] + 1,
            max_guests=CUSTOM_MAX_GUESTS,
            base_price_kopecks=PLAN_PRICES_KOPECKS[top],
            per_guest_kopecks=custom_per_guest_kopecks(),
            retention_days=retention_days(Plan.CUSTOM),
        ),
        frames=PricingFramesOut(
            base_per_guest=_FRAMES_DEFAULT,
            extended_per_guest=_FRAMES_EXTENDED,
            price_per_guest_kopecks=frames_upgrade_price_per_guest_kopecks(),
        ),
        extend=[
            PricingExtendOut(
                period=period,
                days=days,
                price_kopecks=minimum,
                per_guest_kopecks=EXTEND_PER_GUEST_KOPECKS[period] if pricing_v2_active() else 0,
            )
            for period, (days, minimum) in EXTEND_OPTIONS.items()
        ],
        solo_extend=[
            PricingExtendOut(period=period, days=days, price_kopecks=price)
            for period, (days, price) in SOLO_EXTEND_OPTIONS.items()
        ],
        plus=PricingPlusOut(
            enabled=settings.SUBSCRIPTION_ENABLED,
            month_kopecks=settings.SUB_PRICE_MONTH_KOPECKS,
            year_kopecks=settings.SUB_PRICE_YEAR_KOPECKS,
            solo_frames_per_month=settings.SOLO_PLUS_FRAMES_PER_MONTH,
            solo_free_frames_per_month=settings.SOLO_FREE_FRAMES_PER_MONTH,
            solo_retention_days=settings.SOLO_PLUS_RETENTION_DAYS,
            solo_free_retention_days=settings.SOLO_FREE_RETENTION_DAYS,
            events_active=settings.PLUS_FREE_ACTIVE_EVENTS,
            events_per_month=settings.PLUS_FREE_EVENTS_PER_MONTH,
            free_events_active=settings.FREE_ACTIVE_EVENTS or 0,
            free_events_per_month=settings.FREE_EVENTS_PER_MONTH or 0,
            mini_frames_per_album=settings.MINI_PLUS_FRAMES_PER_ALBUM,
            mini_free_albums=settings.MINI_FREE_ALBUMS,
            mini_free_frames_per_album=settings.MINI_FREE_FRAMES_PER_ALBUM,
        ),
        upgrade_premium=_UPGRADE_PREMIUM,
        free_active_events=settings.FREE_ACTIVE_EVENTS,
        free_events_per_month=settings.FREE_EVENTS_PER_MONTH,
    )


async def create_checkout(
    session: AsyncSession,
    user_id: UUID,
    event_id: UUID,
    plan: Plan,
    idempotency_key: str,
    payment_method: str | None = None,
    promocode: str | None = None,
) -> CheckoutOut:
    event = await event_repo.get_by_id(session, event_id)
    if event is None:
        raise NotFoundError("Event not found")
    if event.user_id != user_id:
        raise PermissionDeniedError("Not your event")
    if event.status != EventStatus.DRAFT:
        raise ConflictError(
            "Only draft events can be paid",
            details={"status": event.status.value},
        )

    original_amount = PLAN_PRICES_KOPECKS.get(plan)
    if original_amount is None:
        raise ConflictError(
            "Тариф рассчитывается индивидуально",
            details={"plan": plan.value},
        )
    if original_amount == 0:
        raise ConflictError("Free plan does not require payment")

    existing = await payment_repo.get_by_idempotency_key(session, idempotency_key)
    if existing is not None:
        return CheckoutOut(
            payment_id=existing.id,
            yookassa_id=existing.yookassa_id or "",
            confirmation_url=existing.meta.get("confirmation_url", ""),
            amount_kopecks=existing.amount_kopecks,
            original_amount_kopecks=existing.original_amount_kopecks,
            discount_kopecks=(existing.original_amount_kopecks or existing.amount_kopecks) - existing.amount_kopecks,
            admin_bypass=existing.meta.get("admin_bypass", False),
        )

    user = await user_repo.get_by_id(session, user_id)
    if user is None:
        raise NotFoundError("User not found")

    # Промокод — валидация до создания платежа.
    discount_kopecks = 0
    promocode_id: UUID | None = None
    if promocode:
        vr = await promocode_service.validate_promocode(
            session, code=promocode, user_id=user_id,
            amount_kopecks=original_amount, applies_to="checkout",
        )
        if not vr.valid:
            raise ConflictError(vr.error or "Промокод недействителен")
        discount_kopecks = vr.discount_kopecks
        promocode_id = vr.promocode_id

    amount = max(0, original_amount - discount_kopecks)
    admin_bypass = entitlement_service.has_payment_bypass(user)
    bypass_yookassa = admin_bypass or amount == 0

    from app.services.event_service import _PLAN_LIMITS, default_expires_at

    meta: dict = {"plan": plan.value}
    if admin_bypass:
        meta["admin_bypass"] = True

    if bypass_yookassa:
        payment = Payment(
            event_id=event.id,
            user_id=user_id,
            yookassa_id=None,
            amount_kopecks=amount,
            original_amount_kopecks=original_amount if discount_kopecks > 0 else None,
            status=PaymentStatus.SUCCEEDED,
            idempotency_key=idempotency_key,
            meta=meta,
        )
        await payment_repo.create(session, payment)

        if promocode_id is not None:
            redemption = await promocode_service.apply_promocode(
                session,
                promocode_id=promocode_id,
                user_id=user_id,
                payment_id=payment.id,
                discount_kopecks=discount_kopecks,
            )
            payment.promocode_redemption_id = redemption.id

        # Применить эффект сразу.
        event.settings.plan = plan
        event.settings.max_guests = _PLAN_LIMITS[plan]
        event.status = EventStatus.ACTIVE
        event.activated_at = datetime.now(timezone.utc)
        event.expires_at = default_expires_at(plan)

        await _maybe_issue_referral_reward(session, user, payment)
        await session.commit()

        return CheckoutOut(
            payment_id=payment.id,
            yookassa_id="",
            confirmation_url="",
            amount_kopecks=amount,
            original_amount_kopecks=original_amount if discount_kopecks > 0 else None,
            discount_kopecks=discount_kopecks,
            admin_bypass=admin_bypass,
        )

    yk = await yookassa_client.create_payment(
        event_id=event.id,
        plan=plan.value,
        amount_kopecks=amount,
        idempotency_key=idempotency_key,
        user_email=user.email,
        payment_method=payment_method,
    )

    meta["confirmation_url"] = yk.confirmation_url
    payment = Payment(
        event_id=event.id,
        user_id=user_id,
        yookassa_id=yk.id,
        amount_kopecks=amount,
        original_amount_kopecks=original_amount if discount_kopecks > 0 else None,
        status=PaymentStatus.PENDING,
        idempotency_key=idempotency_key,
        meta=meta,
    )
    await payment_repo.create(session, payment)

    if promocode_id is not None:
        redemption = await promocode_service.apply_promocode(
            session,
            promocode_id=promocode_id,
            user_id=user_id,
            payment_id=payment.id,
            discount_kopecks=discount_kopecks,
        )
        payment.promocode_redemption_id = redemption.id

    event.settings.plan = plan
    event.settings.max_guests = _PLAN_LIMITS[plan]
    await session.commit()

    return CheckoutOut(
        payment_id=payment.id,
        yookassa_id=yk.id,
        confirmation_url=yk.confirmation_url,
        amount_kopecks=amount,
        original_amount_kopecks=original_amount if discount_kopecks > 0 else None,
        discount_kopecks=discount_kopecks,
        admin_bypass=False,
    )


async def _maybe_issue_referral_reward(session: AsyncSession, user, payment: Payment) -> None:
    """Если у юзера первый успешный платный платёж и он был приглашён — выдать
    промокод пригласившему.

    Вызывается из create_checkout admin-bypass ветки (для админа не имеет смысла,
    но кода это не портит) и из handle_webhook при успешной оплате.
    """
    if user.invited_by_user_id is None:
        return
    if payment.amount_kopecks <= 0:
        return
    from sqlalchemy import func, select
    stmt = (
        select(func.count())
        .select_from(Payment)
        .where(
            Payment.user_id == user.id,
            Payment.status == PaymentStatus.SUCCEEDED,
            Payment.amount_kopecks > 0,
        )
    )
    succ_count = int((await session.execute(stmt)).scalar_one())
    # Точно первый — только что создали, до commit; но flush уже был.
    if succ_count != 1:
        return
    try:
        await promocode_service.issue_referral_reward(session, user.invited_by_user_id)
    except Exception as exc:
        logger.error("referral_reward_failed", user_id=str(user.id), error=str(exc))


async def create_extend_checkout(
    session: AsyncSession,
    user_id: UUID,
    event_id: UUID,
    period: ExtendPeriod,
    idempotency_key: str,
    payment_method: str | None = None,
    promocode: str | None = None,
) -> ExtendOut:
    """Create a YooKassa checkout for extending album storage.

    Does not modify event.expires_at — that happens when the webhook confirms payment.
    """
    event = await event_repo.get_by_id(session, event_id)
    if event is None:
        raise NotFoundError("Event not found")
    if event.user_id != user_id:
        raise PermissionDeniedError("Not your event")
    if event.status not in (EventStatus.ACTIVE, EventStatus.COMPLETED):
        raise ConflictError(
            "Only active or completed events can be extended",
            details={"status": event.status.value},
        )

    if period not in EXTEND_OPTIONS:
        raise ConflictError("Unknown extension period", details={"period": period})
    days_added = EXTEND_OPTIONS[period][0]
    if event.kind == "solo":
        original_amount = SOLO_EXTEND_OPTIONS[period][1]
    else:
        original_amount = extend_price_kopecks(period, event.settings.max_guests)

    existing = await payment_repo.get_by_idempotency_key(session, idempotency_key)
    if existing is not None:
        current = event.expires_at or datetime.now(timezone.utc)
        return ExtendOut(
            payment_id=existing.id,
            yookassa_id=existing.yookassa_id or "",
            confirmation_url=existing.meta.get("confirmation_url", ""),
            amount_kopecks=existing.amount_kopecks,
            period=period,
            new_expires_at=current + timedelta(days=days_added),
            days_added=days_added,
            original_amount_kopecks=existing.original_amount_kopecks,
            discount_kopecks=(existing.original_amount_kopecks or existing.amount_kopecks) - existing.amount_kopecks,
            admin_bypass=existing.meta.get("admin_bypass", False),
        )

    user = await user_repo.get_by_id(session, user_id)
    if user is None:
        raise NotFoundError("User not found")

    discount_kopecks = 0
    promocode_id: UUID | None = None
    if promocode:
        vr = await promocode_service.validate_promocode(
            session, code=promocode, user_id=user_id,
            amount_kopecks=original_amount, applies_to="extend",
        )
        if not vr.valid:
            raise ConflictError(vr.error or "Промокод недействителен")
        discount_kopecks = vr.discount_kopecks
        promocode_id = vr.promocode_id

    amount = max(0, original_amount - discount_kopecks)
    admin_bypass = entitlement_service.has_payment_bypass(user)
    bypass_yookassa = admin_bypass or amount == 0

    meta: dict = {
        "kind": "extend",
        "period": period,
        "days_added": days_added,
    }
    if admin_bypass:
        meta["admin_bypass"] = True

    if bypass_yookassa:
        payment = Payment(
            event_id=event.id,
            user_id=user_id,
            yookassa_id=None,
            amount_kopecks=amount,
            original_amount_kopecks=original_amount if discount_kopecks > 0 else None,
            status=PaymentStatus.SUCCEEDED,
            idempotency_key=idempotency_key,
            meta=meta,
        )
        await payment_repo.create(session, payment)
        if promocode_id is not None:
            redemption = await promocode_service.apply_promocode(
                session, promocode_id=promocode_id, user_id=user_id,
                payment_id=payment.id, discount_kopecks=discount_kopecks,
            )
            payment.promocode_redemption_id = redemption.id

        base = event.expires_at or datetime.now(timezone.utc)
        event.expires_at = base + timedelta(days=days_added)
        history = list(event.extension_history or [])
        history.append({
            "days_added": days_added,
            "price_kopecks": amount,
            "period": period,
            "paid_at": datetime.now(timezone.utc).isoformat(),
            "payment_id": str(payment.id),
            "admin_bypass": admin_bypass,
        })
        event.extension_history = history

        await session.commit()
        return ExtendOut(
            payment_id=payment.id,
            yookassa_id="",
            confirmation_url="",
            amount_kopecks=amount,
            period=period,
            new_expires_at=event.expires_at,
            days_added=days_added,
            original_amount_kopecks=original_amount if discount_kopecks > 0 else None,
            discount_kopecks=discount_kopecks,
            admin_bypass=admin_bypass,
        )

    yk = await yookassa_client.create_payment(
        event_id=event.id,
        plan=f"extend_{period}",
        amount_kopecks=amount,
        idempotency_key=idempotency_key,
        user_email=user.email,
        payment_method=payment_method,
    )
    meta["confirmation_url"] = yk.confirmation_url

    payment = Payment(
        event_id=event.id,
        user_id=user_id,
        yookassa_id=yk.id,
        amount_kopecks=amount,
        original_amount_kopecks=original_amount if discount_kopecks > 0 else None,
        status=PaymentStatus.PENDING,
        idempotency_key=idempotency_key,
        meta=meta,
    )
    await payment_repo.create(session, payment)
    if promocode_id is not None:
        redemption = await promocode_service.apply_promocode(
            session, promocode_id=promocode_id, user_id=user_id,
            payment_id=payment.id, discount_kopecks=discount_kopecks,
        )
        payment.promocode_redemption_id = redemption.id
    await session.commit()

    current = event.expires_at or datetime.now(timezone.utc)
    return ExtendOut(
        payment_id=payment.id,
        yookassa_id=yk.id,
        confirmation_url=yk.confirmation_url,
        amount_kopecks=amount,
        period=period,
        new_expires_at=current + timedelta(days=days_added),
        days_added=days_added,
        original_amount_kopecks=original_amount if discount_kopecks > 0 else None,
        discount_kopecks=discount_kopecks,
        admin_bypass=False,
    )


async def create_upgrade_checkout(
    session: AsyncSession,
    user_id: UUID,
    event_id: UUID,
    kind: UpgradeKind,
    idempotency_key: str,
    payment_method: str | None = None,
    promocode: str | None = None,
) -> UpgradeOut:
    """Create a YooKassa checkout for upgrading an active event.

    kind="guests": upgrade to next-tier plan (max_guests grows). Price = (new - old) × 1.15.
    kind="frames": extend frames_per_guest from 30 to 45. Price = max_guests × 5 ₽.

    Actual application happens in webhook after payment succeeds.
    """
    event = await event_repo.get_by_id(session, event_id)
    if event is None:
        raise NotFoundError("Event not found")
    if event.user_id != user_id:
        raise PermissionDeniedError("Not your event")
    if event.status not in (EventStatus.ACTIVE, EventStatus.COMPLETED):
        raise ConflictError(
            "Only active or completed events can be upgraded",
            details={"status": event.status.value},
        )

    if event.kind == "solo":
        raise ConflictError("Для соло-альбома доплата за гостей и кадры недоступна")

    meta: dict = {"kind": f"upgrade_{kind}"}

    if kind == "guests":
        current_plan = event.settings.plan
        next_plan = _UPGRADE_GUESTS_PATH.get(current_plan)
        if next_plan is None:
            raise ConflictError(
                "Maximum plan reached — cannot upgrade further",
                details={"current_plan": current_plan.value},
            )
        current_price = PLAN_PRICES_KOPECKS[current_plan]
        next_price = PLAN_PRICES_KOPECKS[next_plan]
        original_amount = int((next_price - current_price) * _UPGRADE_PREMIUM)
        if original_amount <= 0:
            raise ConflictError("Invalid upgrade pricing", details={"amount": original_amount})
        meta["from_plan"] = current_plan.value
        meta["to_plan"] = next_plan.value

    elif kind == "frames":
        current_frames = event.settings.frames_per_guest
        if current_frames >= _FRAMES_EXTENDED:
            raise ConflictError(
                "Frames already at maximum",
                details={"current_frames": current_frames},
            )
        max_guests = event.settings.max_guests
        original_amount = max_guests * frames_upgrade_price_per_guest_kopecks()
        meta["from_frames"] = current_frames
        meta["to_frames"] = _FRAMES_EXTENDED

    else:
        raise ConflictError("Unknown upgrade kind", details={"kind": kind})

    existing = await payment_repo.get_by_idempotency_key(session, idempotency_key)
    if existing is not None:
        return _upgrade_out_from_payment(existing, event, kind, meta)

    user = await user_repo.get_by_id(session, user_id)
    if user is None:
        raise NotFoundError("User not found")

    discount_kopecks = 0
    promocode_id: UUID | None = None
    if promocode:
        vr = await promocode_service.validate_promocode(
            session, code=promocode, user_id=user_id,
            amount_kopecks=original_amount, applies_to="upgrade",
        )
        if not vr.valid:
            raise ConflictError(vr.error or "Промокод недействителен")
        discount_kopecks = vr.discount_kopecks
        promocode_id = vr.promocode_id

    amount = max(0, original_amount - discount_kopecks)
    admin_bypass = entitlement_service.has_payment_bypass(user)
    bypass_yookassa = admin_bypass or amount == 0
    if admin_bypass:
        meta["admin_bypass"] = True

    if bypass_yookassa:
        payment = Payment(
            event_id=event.id,
            user_id=user_id,
            yookassa_id=None,
            amount_kopecks=amount,
            original_amount_kopecks=original_amount if discount_kopecks > 0 else None,
            status=PaymentStatus.SUCCEEDED,
            idempotency_key=idempotency_key,
            meta=meta,
        )
        await payment_repo.create(session, payment)
        if promocode_id is not None:
            redemption = await promocode_service.apply_promocode(
                session, promocode_id=promocode_id, user_id=user_id,
                payment_id=payment.id, discount_kopecks=discount_kopecks,
            )
            payment.promocode_redemption_id = redemption.id

        # Применить upgrade сразу.
        from app.services.event_service import _PLAN_LIMITS
        if kind == "guests":
            to_plan = Plan(meta["to_plan"])
            event.settings.plan = to_plan
            event.settings.max_guests = _PLAN_LIMITS[to_plan]
        else:
            event.settings.frames_per_guest = _FRAMES_EXTENDED

        await session.commit()
        out = _upgrade_out_from_payment(payment, event, kind, meta)
        out.original_amount_kopecks = original_amount if discount_kopecks > 0 else None
        out.discount_kopecks = discount_kopecks
        out.admin_bypass = admin_bypass
        return out

    yk = await yookassa_client.create_payment(
        event_id=event.id,
        plan=f"upgrade_{kind}",
        amount_kopecks=amount,
        idempotency_key=idempotency_key,
        user_email=user.email,
        payment_method=payment_method,
    )
    meta["confirmation_url"] = yk.confirmation_url

    payment = Payment(
        event_id=event.id,
        user_id=user_id,
        yookassa_id=yk.id,
        amount_kopecks=amount,
        original_amount_kopecks=original_amount if discount_kopecks > 0 else None,
        status=PaymentStatus.PENDING,
        idempotency_key=idempotency_key,
        meta=meta,
    )
    await payment_repo.create(session, payment)
    if promocode_id is not None:
        redemption = await promocode_service.apply_promocode(
            session, promocode_id=promocode_id, user_id=user_id,
            payment_id=payment.id, discount_kopecks=discount_kopecks,
        )
        payment.promocode_redemption_id = redemption.id
    await session.commit()

    out = _upgrade_out_from_payment(payment, event, kind, meta)
    out.original_amount_kopecks = original_amount if discount_kopecks > 0 else None
    out.discount_kopecks = discount_kopecks
    return out


def _upgrade_out_from_payment(payment: Payment, event, kind: UpgradeKind, meta: dict) -> UpgradeOut:
    from app.services.event_service import _PLAN_LIMITS
    out = UpgradeOut(
        payment_id=payment.id,
        yookassa_id=payment.yookassa_id or "",
        confirmation_url=payment.meta.get("confirmation_url", meta.get("confirmation_url", "")),
        amount_kopecks=payment.amount_kopecks,
        kind=kind,
        original_amount_kopecks=payment.original_amount_kopecks,
        discount_kopecks=(payment.original_amount_kopecks or payment.amount_kopecks) - payment.amount_kopecks,
        admin_bypass=payment.meta.get("admin_bypass", False),
    )
    if kind == "guests":
        to_plan_str = payment.meta.get("to_plan") or meta.get("to_plan")
        if to_plan_str:
            to_plan = Plan(to_plan_str)
            out.new_plan = to_plan_str
            out.new_max_guests = _PLAN_LIMITS.get(to_plan)
    elif kind == "frames":
        out.new_frames_per_guest = _FRAMES_EXTENDED
    return out


_YK_STATUS_MAP = {
    "succeeded": PaymentStatus.SUCCEEDED,
    "canceled": PaymentStatus.CANCELLED,
    "refunded": PaymentStatus.REFUNDED,
    "waiting_for_capture": PaymentStatus.PENDING,
    "pending": PaymentStatus.PENDING,
}


async def _resolve_webhook_status(
    payment: Payment, event_name: str | None, obj: dict
) -> tuple[PaymentStatus, str] | None:
    """Возвращает (новый статус, статус YooKassa) или None, если менять нечего.

    Тело вебхука не подписано, поэтому в боевом режиме статус и суммы берём
    из API YooKassa. Без ключей (mock/тесты) доверяем телу.
    """
    is_refund = event_name == "refund.succeeded"

    if yookassa_client.is_configured():
        info = await yookassa_client.fetch_payment(payment.yookassa_id)
        if info.amount_kopecks != payment.amount_kopecks:
            logger.error(
                "yookassa_webhook_amount_mismatch",
                payment_id=str(payment.id),
                expected=payment.amount_kopecks,
                actual=info.amount_kopecks,
            )
            return None
        if is_refund or info.status == "refunded":
            if info.refunded_kopecks < payment.amount_kopecks:
                logger.warning(
                    "yookassa_partial_refund_ignored",
                    payment_id=str(payment.id),
                    refunded=info.refunded_kopecks,
                )
                return None
            return PaymentStatus.REFUNDED, "refunded"
        return _YK_STATUS_MAP.get(info.status, PaymentStatus.PENDING), info.status

    if is_refund:
        refunded = int(round(float((obj.get("amount") or {}).get("value", 0)) * 100))
        if refunded < payment.amount_kopecks:
            logger.warning(
                "yookassa_partial_refund_ignored",
                payment_id=str(payment.id),
                refunded=refunded,
            )
            return None
        return PaymentStatus.REFUNDED, "refunded"
    yk_status = obj.get("status", "pending")
    return _YK_STATUS_MAP.get(yk_status, PaymentStatus.PENDING), yk_status


async def _subscription_method_id(payment: Payment, obj: dict) -> str | None:
    """Сохранённый способ оплаты для автосписаний. В боевом режиме берём из API ЮKassa."""
    if yookassa_client.is_configured() and payment.yookassa_id:
        info = await yookassa_client.fetch_payment(payment.yookassa_id)
        return info.payment_method_id if info.payment_method_saved else None
    method = obj.get("payment_method") or {}
    return method.get("id") if method.get("saved") else None


async def handle_webhook(session: AsyncSession, payload: dict) -> None:
    event_name = payload.get("event")
    obj = payload.get("object") or {}
    # refund.succeeded присылает объект возврата: id — это id возврата,
    # а платёж указан в payment_id.
    if event_name == "refund.succeeded":
        yookassa_id = obj.get("payment_id")
    else:
        yookassa_id = obj.get("id")
    if not yookassa_id:
        logger.warning("yookassa_webhook_missing_id", webhook_event=event_name)
        return

    # SELECT ... FOR UPDATE — блокируем Payment row, чтобы retry YooKassa не
    # применил upgrade/extend дважды при конкурентной обработке двух webhook.
    payment = await payment_repo.get_by_yookassa_id_for_update(session, yookassa_id)
    if payment is None:
        logger.warning("yookassa_webhook_unknown_payment", yookassa_id=yookassa_id)
        return

    resolved = await _resolve_webhook_status(payment, event_name, obj)
    if resolved is None:
        return
    new_status, yk_status = resolved

    # Идемпотентность: терминальное состояние не переходит обратно.
    # SUCCEEDED → REFUNDED разрешено (возврат). REFUNDED → что угодно запрещено.
    if payment.status == PaymentStatus.REFUNDED:
        logger.info("yookassa_webhook_already_refunded", payment_id=str(payment.id))
        return
    if payment.status == PaymentStatus.SUCCEEDED and new_status != PaymentStatus.REFUNDED:
        logger.info("yookassa_webhook_already_applied", payment_id=str(payment.id))
        return

    if payment.status == new_status:
        logger.info("yookassa_webhook_no_change", payment_id=str(payment.id))
        return

    prior_status = payment.status
    payment.status = new_status
    payment.meta = {**payment.meta, "last_webhook_event": event_name, "yookassa_status": yk_status}

    is_subscription = payment.meta.get("kind") == "subscription"

    if new_status == PaymentStatus.SUCCEEDED:
        if is_subscription:
            method_id = await _subscription_method_id(payment, obj)
            await subscription_service.apply_succeeded_payment(session, payment, method_id)
            event = None
        else:
            event = await event_repo.get_by_id(session, payment.event_id)
        if event is not None:
            kind = payment.meta.get("kind")
            if kind == "extend":
                # Storage extension — extend expires_at and log to history.
                days = int(payment.meta.get("days_added", 0))
                if days > 0:
                    base = event.expires_at or datetime.now(timezone.utc)
                    event.expires_at = base + timedelta(days=days)
                    history = list(event.extension_history or [])
                    history.append({
                        "days_added": days,
                        "price_kopecks": payment.amount_kopecks,
                        "period": payment.meta.get("period"),
                        "paid_at": datetime.now(timezone.utc).isoformat(),
                        "payment_id": str(payment.id),
                    })
                    event.extension_history = history
                    logger.info(
                        "storage_extended",
                        event_id=str(event.id),
                        days=days,
                        new_expires_at=event.expires_at.isoformat(),
                    )
            elif kind == "upgrade_guests":
                # Guest count upgrade — bump event.settings.plan and max_guests.
                from app.services.event_service import _PLAN_LIMITS
                to_plan_str = payment.meta.get("to_plan")
                if to_plan_str:
                    to_plan = Plan(to_plan_str)
                    event.settings.plan = to_plan
                    event.settings.max_guests = _PLAN_LIMITS[to_plan]
                    logger.info(
                        "upgrade_guests_applied",
                        event_id=str(event.id),
                        from_plan=payment.meta.get("from_plan"),
                        to_plan=to_plan_str,
                        new_max_guests=event.settings.max_guests,
                    )
            elif kind == "upgrade_frames":
                # Frames per guest upgrade — 30 → 45.
                to_frames = int(payment.meta.get("to_frames", _FRAMES_EXTENDED))
                event.settings.frames_per_guest = to_frames
                logger.info(
                    "upgrade_frames_applied",
                    event_id=str(event.id),
                    new_frames_per_guest=to_frames,
                )
            elif event.status == EventStatus.DRAFT:
                # Первичная оплата: тариф берём из платежа, а не из черновика —
                # черновик могли поменять после создания платежа.
                from app.services.event_service import _PLAN_LIMITS, default_expires_at
                paid_plan_str = payment.meta.get("plan")
                paid_plan = Plan(paid_plan_str) if paid_plan_str else event.settings.plan
                event.settings.plan = paid_plan
                event.settings.max_guests = _PLAN_LIMITS[paid_plan]
                event.status = EventStatus.ACTIVE
                event.activated_at = datetime.now(timezone.utc)
                event.expires_at = default_expires_at(paid_plan)
            else:
                # Черновик успели активировать бесплатно до прихода вебхука —
                # оплаченный тариф всё равно применяем, если он больше текущего.
                from app.services.event_service import _PLAN_LIMITS
                paid_plan_str = payment.meta.get("plan")
                if paid_plan_str:
                    paid_plan = Plan(paid_plan_str)
                    if _PLAN_LIMITS[paid_plan] > event.settings.max_guests:
                        event.settings.plan = paid_plan
                        event.settings.max_guests = _PLAN_LIMITS[paid_plan]
                        logger.info(
                            "late_checkout_plan_applied",
                            event_id=str(event.id),
                            plan=paid_plan_str,
                        )

        # Выдача реферальной награды при первом успешном платном платеже юзера.
        user = await user_repo.get_by_id(session, payment.user_id)
        if user is not None and not is_subscription:
            await _maybe_issue_referral_reward(session, user, payment)

    elif new_status == PaymentStatus.CANCELLED and is_subscription:
        await subscription_service.apply_failed_payment(session, payment)

    elif new_status == PaymentStatus.CANCELLED and payment.promocode_redemption_id is not None:
        redemption_id = payment.promocode_redemption_id
        payment.promocode_redemption_id = None
        await session.flush()
        await promocode_service.release_redemption(session, redemption_id)

    elif new_status == PaymentStatus.REFUNDED and prior_status == PaymentStatus.SUCCEEDED:
        # Возврат средств — откатываем эффект, который был применён при SUCCEEDED.
        if is_subscription:
            await subscription_service.apply_refund(session, payment)
            event = None
        else:
            event = await event_repo.get_by_id(session, payment.event_id)
        if event is not None:
            kind = payment.meta.get("kind")
            if kind == "extend":
                # Откатить expires_at и вычеркнуть последнюю запись расширения.
                days = int(payment.meta.get("days_added", 0))
                if days > 0 and event.expires_at is not None:
                    event.expires_at = event.expires_at - timedelta(days=days)
                history = list(event.extension_history or [])
                if history:
                    last = history[-1]
                    if last.get("payment_id") == str(payment.id):
                        history.pop()
                        event.extension_history = history
                logger.info(
                    "storage_extension_refunded",
                    event_id=str(event.id),
                    days_reverted=days,
                )
            elif kind == "upgrade_guests":
                from app.services.event_service import _PLAN_LIMITS
                from_plan_str = payment.meta.get("from_plan")
                if from_plan_str:
                    from_plan = Plan(from_plan_str)
                    event.settings.plan = from_plan
                    event.settings.max_guests = _PLAN_LIMITS[from_plan]
                    logger.info(
                        "upgrade_guests_refunded",
                        event_id=str(event.id),
                        reverted_to=from_plan_str,
                    )
            elif kind == "upgrade_frames":
                from_frames = int(payment.meta.get("from_frames", _FRAMES_DEFAULT))
                event.settings.frames_per_guest = from_frames
                logger.info(
                    "upgrade_frames_refunded",
                    event_id=str(event.id),
                    reverted_to=from_frames,
                )
            else:
                # Возврат первичной оплаты — событие возвращается в DRAFT, plan → FREE.
                event.status = EventStatus.DRAFT
                event.settings.plan = Plan.FREE
                from app.services.event_service import _PLAN_LIMITS
                event.settings.max_guests = _PLAN_LIMITS[Plan.FREE]
                event.expires_at = None
                logger.info(
                    "checkout_refunded",
                    event_id=str(event.id),
                    payment_id=str(payment.id),
                )

    await session.commit()
    logger.info(
        "yookassa_webhook_processed",
        payment_id=str(payment.id),
        new_status=new_status.value,
    )
