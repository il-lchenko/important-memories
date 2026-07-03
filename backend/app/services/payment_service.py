from datetime import datetime, timedelta, timezone
from uuid import UUID, uuid4

from sqlalchemy.ext.asyncio import AsyncSession

from app.core.errors import (
    ConflictError,
    NotFoundError,
    PermissionDeniedError,
)
from app.core.logging import logger
from app.domain.models import EventStatus, Payment, PaymentStatus, Plan
from app.domain.schemas.payments import CheckoutOut, ExtendOut, ExtendPeriod, UpgradeKind, UpgradeOut
from app.infra import yookassa_client
from app.repos import event_repo, payment_repo, user_repo

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

# Storage extension: (days added, price in kopecks). Business plan v3.2 section 10.
EXTEND_OPTIONS: dict[str, tuple[int, int]] = {
    "3m": (90, 49000),    # 490 ₽
    "6m": (180, 79000),   # 790 ₽
    "1y": (365, 129000),  # 1 290 ₽
}

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

# Extended frames per guest (default 30, extension 45). Price: 5 ₽/guest.
_FRAMES_EXTENDED = 45
_FRAMES_DEFAULT = 30
_FRAMES_UPGRADE_PRICE_PER_GUEST_KOPECKS = 500


async def create_checkout(
    session: AsyncSession,
    user_id: UUID,
    event_id: UUID,
    plan: Plan,
    idempotency_key: str,
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

    amount = PLAN_PRICES_KOPECKS[plan]
    if amount == 0:
        raise ConflictError("Free plan does not require payment")

    existing = await payment_repo.get_by_idempotency_key(session, idempotency_key)
    if existing is not None:
        return CheckoutOut(
            payment_id=existing.id,
            yookassa_id=existing.yookassa_id,
            confirmation_url=existing.meta.get("confirmation_url", ""),
            amount_kopecks=existing.amount_kopecks,
        )

    user = await user_repo.get_by_id(session, user_id)
    assert user is not None

    yk = await yookassa_client.create_payment(
        event_id=event.id,
        plan=plan.value,
        amount_kopecks=amount,
        idempotency_key=idempotency_key,
        user_email=user.email,
    )

    payment = Payment(
        event_id=event.id,
        user_id=user_id,
        yookassa_id=yk.id,
        amount_kopecks=amount,
        status=PaymentStatus.PENDING,
        idempotency_key=idempotency_key,
        meta={"plan": plan.value, "confirmation_url": yk.confirmation_url},
    )
    await payment_repo.create(session, payment)
    event.settings.plan = plan
    from app.services.event_service import _PLAN_LIMITS

    event.settings.max_guests = _PLAN_LIMITS[plan]
    await session.commit()

    return CheckoutOut(
        payment_id=payment.id,
        yookassa_id=yk.id,
        confirmation_url=yk.confirmation_url,
        amount_kopecks=amount,
    )


async def create_extend_checkout(
    session: AsyncSession,
    user_id: UUID,
    event_id: UUID,
    period: ExtendPeriod,
    idempotency_key: str,
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
    days_added, amount = EXTEND_OPTIONS[period]

    existing = await payment_repo.get_by_idempotency_key(session, idempotency_key)
    if existing is not None:
        current = event.expires_at or datetime.now(timezone.utc)
        return ExtendOut(
            payment_id=existing.id,
            yookassa_id=existing.yookassa_id,
            confirmation_url=existing.meta.get("confirmation_url", ""),
            amount_kopecks=existing.amount_kopecks,
            period=period,
            new_expires_at=current + timedelta(days=days_added),
            days_added=days_added,
        )

    user = await user_repo.get_by_id(session, user_id)
    assert user is not None

    yk = await yookassa_client.create_payment(
        event_id=event.id,
        plan=f"extend_{period}",
        amount_kopecks=amount,
        idempotency_key=idempotency_key,
        user_email=user.email,
    )

    payment = Payment(
        event_id=event.id,
        user_id=user_id,
        yookassa_id=yk.id,
        amount_kopecks=amount,
        status=PaymentStatus.PENDING,
        idempotency_key=idempotency_key,
        meta={
            "kind": "extend",
            "period": period,
            "days_added": days_added,
            "confirmation_url": yk.confirmation_url,
        },
    )
    await payment_repo.create(session, payment)
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
    )


async def create_upgrade_checkout(
    session: AsyncSession,
    user_id: UUID,
    event_id: UUID,
    kind: UpgradeKind,
    idempotency_key: str,
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
        amount = int((next_price - current_price) * _UPGRADE_PREMIUM)
        if amount <= 0:
            raise ConflictError("Invalid upgrade pricing", details={"amount": amount})
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
        amount = max_guests * _FRAMES_UPGRADE_PRICE_PER_GUEST_KOPECKS
        meta["from_frames"] = current_frames
        meta["to_frames"] = _FRAMES_EXTENDED

    else:
        raise ConflictError("Unknown upgrade kind", details={"kind": kind})

    existing = await payment_repo.get_by_idempotency_key(session, idempotency_key)
    if existing is not None:
        return _upgrade_out_from_payment(existing, event, kind, meta)

    user = await user_repo.get_by_id(session, user_id)
    assert user is not None

    yk = await yookassa_client.create_payment(
        event_id=event.id,
        plan=f"upgrade_{kind}",
        amount_kopecks=amount,
        idempotency_key=idempotency_key,
        user_email=user.email,
    )
    meta["confirmation_url"] = yk.confirmation_url

    payment = Payment(
        event_id=event.id,
        user_id=user_id,
        yookassa_id=yk.id,
        amount_kopecks=amount,
        status=PaymentStatus.PENDING,
        idempotency_key=idempotency_key,
        meta=meta,
    )
    await payment_repo.create(session, payment)
    await session.commit()

    return _upgrade_out_from_payment(payment, event, kind, meta)


def _upgrade_out_from_payment(payment: Payment, event, kind: UpgradeKind, meta: dict) -> UpgradeOut:
    from app.services.event_service import _PLAN_LIMITS
    out = UpgradeOut(
        payment_id=payment.id,
        yookassa_id=payment.yookassa_id,
        confirmation_url=payment.meta.get("confirmation_url", meta.get("confirmation_url", "")),
        amount_kopecks=payment.amount_kopecks,
        kind=kind,
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


async def handle_webhook(session: AsyncSession, payload: dict) -> None:
    event_name = payload.get("event")
    obj = payload.get("object") or {}
    yookassa_id = obj.get("id")
    if not yookassa_id:
        logger.warning("yookassa_webhook_missing_id", payload=payload)
        return

    payment = await payment_repo.get_by_yookassa_id(session, yookassa_id)
    if payment is None:
        logger.warning("yookassa_webhook_unknown_payment", yookassa_id=yookassa_id)
        return

    yk_status = obj.get("status", "pending")
    status_map = {
        "succeeded": PaymentStatus.SUCCEEDED,
        "canceled": PaymentStatus.CANCELLED,
        "waiting_for_capture": PaymentStatus.PENDING,
        "pending": PaymentStatus.PENDING,
    }
    new_status = status_map.get(yk_status, PaymentStatus.PENDING)

    if payment.status == new_status:
        logger.info("yookassa_webhook_no_change", payment_id=str(payment.id))
        return

    payment.status = new_status
    payment.meta = {**payment.meta, "last_webhook_event": event_name, "yookassa_status": yk_status}

    if new_status == PaymentStatus.SUCCEEDED:
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
                # Initial plan checkout — activate event and set storage expiration.
                from app.services.event_service import default_expires_at
                event.status = EventStatus.ACTIVE
                if event.expires_at is None:
                    event.expires_at = default_expires_at(event.settings.plan)

    await session.commit()
    logger.info(
        "yookassa_webhook_processed",
        payment_id=str(payment.id),
        new_status=new_status.value,
    )
