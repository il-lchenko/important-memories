import asyncio
from dataclasses import dataclass
from uuid import UUID, uuid4

from app.core.config import settings
from app.core.errors import ExternalServiceError
from app.core.logging import logger


@dataclass
class YookassaPayment:
    id: str
    confirmation_url: str
    status: str


def _is_configured() -> bool:
    return bool(settings.YOOKASSA_SHOP_ID and settings.YOOKASSA_SECRET.get_secret_value())


def _build_metadata(event_id: UUID, plan: str, user_email: str) -> dict:
    return {
        "event_id": str(event_id),
        "plan": plan,
        "user_email": user_email,
    }


def _create_mock(amount_kopecks: int, idempotency_key: str) -> YookassaPayment:
    payment_id = f"mock_{uuid4().hex[:24]}"
    return_url = f"{settings.PUBLIC_PWA_BASE_URL}/payment/return?payment_id={payment_id}"
    confirmation_url = (
        f"{settings.PUBLIC_API_BASE_URL}/dev/yookassa/checkout"
        f"?payment_id={payment_id}&amount_kopecks={amount_kopecks}&return_url={return_url}"
    )
    return YookassaPayment(id=payment_id, confirmation_url=confirmation_url, status="pending")


def _create_real_sync(
    amount_kopecks: int,
    idempotency_key: str,
    return_url: str,
    description: str,
    metadata: dict,
    user_email: str,
) -> YookassaPayment:
    from yookassa import Configuration, Payment

    Configuration.account_id = settings.YOOKASSA_SHOP_ID
    Configuration.secret_key = settings.YOOKASSA_SECRET.get_secret_value()

    body = {
        "amount": {
            "value": f"{amount_kopecks / 100:.2f}",
            "currency": "RUB",
        },
        "capture": True,
        "confirmation": {"type": "redirect", "return_url": return_url},
        "description": description,
        "metadata": metadata,
        "receipt": {
            "customer": {"email": user_email},
            "items": [
                {
                    "description": description,
                    "quantity": "1.00",
                    "amount": {"value": f"{amount_kopecks / 100:.2f}", "currency": "RUB"},
                    "vat_code": 1,
                    "payment_subject": "service",
                    "payment_mode": "full_payment",
                }
            ],
        },
    }
    try:
        payment = Payment.create(body, idempotency_key)
    except Exception as exc:
        logger.error("yookassa_create_failed", error=str(exc))
        raise ExternalServiceError("YooKassa create failed") from exc

    return YookassaPayment(
        id=payment.id,
        confirmation_url=payment.confirmation.confirmation_url,
        status=payment.status,
    )


async def create_payment(
    *,
    event_id: UUID,
    plan: str,
    amount_kopecks: int,
    idempotency_key: str,
    user_email: str,
) -> YookassaPayment:
    return_url = f"{settings.PUBLIC_PWA_BASE_URL}/payment/return"
    description = f"Important Memories — тариф {plan}, ивент {event_id}"
    metadata = _build_metadata(event_id, plan, user_email)

    if not _is_configured():
        logger.warning("yookassa_mock_mode", event_id=str(event_id), plan=plan)
        return _create_mock(amount_kopecks, idempotency_key)

    return await asyncio.to_thread(
        _create_real_sync,
        amount_kopecks,
        idempotency_key,
        return_url,
        description,
        metadata,
        user_email,
    )
