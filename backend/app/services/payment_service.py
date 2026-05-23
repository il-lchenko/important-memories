import hashlib
import hmac
from uuid import UUID, uuid4

from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.core.errors import (
    AuthError,
    ConflictError,
    NotFoundError,
    PermissionDeniedError,
)
from app.core.logging import logger
from app.domain.models import EventStatus, Payment, PaymentStatus, Plan
from app.domain.schemas.payments import CheckoutOut
from app.infra import yookassa_client
from app.repos import event_repo, payment_repo, user_repo

PLAN_PRICES_KOPECKS: dict[Plan, int] = {
    Plan.FREE: 0,
    Plan.P10: 9900,
    Plan.P50: 99000,
    Plan.P150: 199000,
    Plan.UNLIMITED: 299000,
}


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


def verify_webhook_signature(raw_body: bytes, header_signature: str | None) -> None:
    """Tech-spec NFR-014: HMAC-SHA256 over raw body.

    The header is expected as `sha256=<hexdigest>` (compatible with common YooKassa proxy setups).
    """
    if not header_signature:
        raise AuthError("Missing webhook signature")
    expected = hmac.new(
        settings.YOOKASSA_WEBHOOK_SECRET.get_secret_value().encode(),
        raw_body,
        hashlib.sha256,
    ).hexdigest()
    provided = header_signature.split("=", 1)[1] if "=" in header_signature else header_signature
    if not hmac.compare_digest(expected, provided):
        raise AuthError("Invalid webhook signature")


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
        if event is not None and event.status == EventStatus.DRAFT:
            event.status = EventStatus.ACTIVE

    await session.commit()
    logger.info(
        "yookassa_webhook_processed",
        payment_id=str(payment.id),
        new_status=new_status.value,
    )
