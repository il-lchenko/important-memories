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


@dataclass
class YookassaPaymentInfo:
    id: str
    status: str
    amount_kopecks: int
    refunded_kopecks: int
    # Способ оплаты: id и сохранён ли он для автосписаний (подписка).
    payment_method_id: str | None = None
    payment_method_saved: bool = False


def _is_configured() -> bool:
    return bool(settings.YOOKASSA_SHOP_ID and settings.YOOKASSA_SECRET.get_secret_value())


def is_configured() -> bool:
    return _is_configured()


def _to_kopecks(amount: object) -> int:
    value = getattr(amount, "value", None)
    if value is None and isinstance(amount, dict):
        value = amount.get("value")
    if value is None:
        return 0
    return int(round(float(value) * 100))


def _fetch_real_sync(yookassa_id: str) -> YookassaPaymentInfo:
    from yookassa import Configuration, Payment

    Configuration.account_id = settings.YOOKASSA_SHOP_ID
    Configuration.secret_key = settings.YOOKASSA_SECRET.get_secret_value()
    payment = Payment.find_one(yookassa_id)
    method = getattr(payment, "payment_method", None)
    return YookassaPaymentInfo(
        id=payment.id,
        status=payment.status,
        amount_kopecks=_to_kopecks(payment.amount),
        refunded_kopecks=_to_kopecks(getattr(payment, "refunded_amount", None)),
        payment_method_id=getattr(method, "id", None),
        payment_method_saved=bool(getattr(method, "saved", False)),
    )


async def fetch_payment(yookassa_id: str) -> YookassaPaymentInfo:
    """Webhook-тело YooKassa не подписано, поэтому статус и сумму берём из API."""
    try:
        return await asyncio.wait_for(
            asyncio.to_thread(_fetch_real_sync, yookassa_id),
            timeout=10.0,
        )
    except asyncio.TimeoutError as exc:
        logger.error("yookassa_fetch_timeout", yookassa_id=yookassa_id)
        raise ExternalServiceError("YooKassa timeout") from exc
    except Exception as exc:
        logger.error("yookassa_fetch_failed", yookassa_id=yookassa_id, error=type(exc).__name__)
        raise ExternalServiceError("YooKassa fetch failed") from exc


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


# Разрешённые payment_method_data.type для YooKassa — см. docs.
_ALLOWED_METHODS = {"sbp", "bank_card", "yoo_money", "sberbank"}


def _create_real_sync(
    amount_kopecks: int,
    idempotency_key: str,
    return_url: str,
    description: str,
    metadata: dict,
    user_email: str,
    payment_method: str | None,
) -> YookassaPayment:
    from yookassa import Configuration, Payment

    Configuration.account_id = settings.YOOKASSA_SHOP_ID
    Configuration.secret_key = settings.YOOKASSA_SECRET.get_secret_value()

    body: dict = {
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
    # Если хотим предзапросить конкретный способ (СБП) — YooKassa покажет только его.
    # Без payment_method_data клиент выбирает на странице YooKassa (карта / СБП / кошелёк).
    if payment_method and payment_method in _ALLOWED_METHODS:
        body["payment_method_data"] = {"type": payment_method}

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
    payment_method: str | None = None,
) -> YookassaPayment:
    return_url = f"{settings.PUBLIC_PWA_BASE_URL}/payment/return"
    description = f"Important Memories — тариф {plan}, ивент {event_id}"
    metadata = _build_metadata(event_id, plan, user_email)

    if not _is_configured():
        logger.warning("yookassa_mock_mode", event_id=str(event_id), plan=plan)
        return _create_mock(amount_kopecks, idempotency_key)

    try:
        return await asyncio.wait_for(
            asyncio.to_thread(
                _create_real_sync,
                amount_kopecks,
                idempotency_key,
                return_url,
                description,
                metadata,
                user_email,
                payment_method,
            ),
            timeout=10.0,
        )
    except asyncio.TimeoutError as exc:
        logger.error("yookassa_timeout", event_id=str(event_id), plan=plan)
        raise ExternalServiceError("YooKassa timeout") from exc


# ── Подписка: первый платёж с сохранением способа оплаты и автосписания ───────

def _receipt(description: str, amount_kopecks: int, user_email: str) -> dict:
    return {
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
    }


def _subscription_first_sync(
    amount_kopecks: int, idempotency_key: str, return_url: str, description: str,
    metadata: dict, user_email: str, payment_method: str | None,
) -> YookassaPayment:
    from yookassa import Configuration, Payment

    Configuration.account_id = settings.YOOKASSA_SHOP_ID
    Configuration.secret_key = settings.YOOKASSA_SECRET.get_secret_value()
    body: dict = {
        "amount": {"value": f"{amount_kopecks / 100:.2f}", "currency": "RUB"},
        "capture": True,
        "save_payment_method": True,
        "confirmation": {"type": "redirect", "return_url": return_url},
        "description": description,
        "metadata": metadata,
        "receipt": _receipt(description, amount_kopecks, user_email),
    }
    if payment_method and payment_method in _ALLOWED_METHODS:
        body["payment_method_data"] = {"type": payment_method}
    try:
        payment = Payment.create(body, idempotency_key)
    except Exception as exc:
        logger.error("yookassa_subscription_create_failed", error=str(exc))
        raise ExternalServiceError("YooKassa create failed") from exc
    return YookassaPayment(
        id=payment.id, confirmation_url=payment.confirmation.confirmation_url, status=payment.status
    )


async def create_subscription_payment(
    *,
    user_id: UUID,
    period: str,
    amount_kopecks: int,
    idempotency_key: str,
    user_email: str,
    payment_method: str | None = None,
) -> YookassaPayment:
    return_url = f"{settings.PUBLIC_PWA_BASE_URL}/payment/return?kind=subscription"
    description = "Подписка ImpoMento Плюс" + (" на год" if period == "year" else " на месяц")
    metadata = {"kind": "subscription", "period": period, "user_id": str(user_id)}
    if not _is_configured():
        logger.warning("yookassa_mock_mode", user_id=str(user_id), kind="subscription")
        return _create_mock(amount_kopecks, idempotency_key)
    try:
        return await asyncio.wait_for(
            asyncio.to_thread(
                _subscription_first_sync, amount_kopecks, idempotency_key, return_url,
                description, metadata, user_email, payment_method,
            ),
            timeout=10.0,
        )
    except asyncio.TimeoutError as exc:
        logger.error("yookassa_timeout", user_id=str(user_id), kind="subscription")
        raise ExternalServiceError("YooKassa timeout") from exc


def _charge_saved_sync(
    amount_kopecks: int, idempotency_key: str, description: str, metadata: dict,
    user_email: str, payment_method_id: str,
) -> YookassaPayment:
    from yookassa import Configuration, Payment

    Configuration.account_id = settings.YOOKASSA_SHOP_ID
    Configuration.secret_key = settings.YOOKASSA_SECRET.get_secret_value()
    body = {
        "amount": {"value": f"{amount_kopecks / 100:.2f}", "currency": "RUB"},
        "capture": True,
        "payment_method_id": payment_method_id,
        "description": description,
        "metadata": metadata,
        "receipt": _receipt(description, amount_kopecks, user_email),
    }
    try:
        payment = Payment.create(body, idempotency_key)
    except Exception as exc:
        logger.error("yookassa_charge_saved_failed", error=str(exc))
        raise ExternalServiceError("YooKassa charge failed") from exc
    return YookassaPayment(id=payment.id, confirmation_url="", status=payment.status)


async def charge_saved_method(
    *,
    user_id: UUID,
    period: str,
    amount_kopecks: int,
    idempotency_key: str,
    user_email: str,
    payment_method_id: str,
) -> YookassaPayment:
    """Автосписание очередного периода подписки по сохранённому способу оплаты."""
    description = "Подписка ImpoMento Плюс" + (" на год" if period == "year" else " на месяц")
    metadata = {"kind": "subscription", "period": period, "user_id": str(user_id), "renewal": "1"}
    if not _is_configured():
        return YookassaPayment(id=f"mock_{uuid4().hex[:24]}", confirmation_url="", status="pending")
    try:
        return await asyncio.wait_for(
            asyncio.to_thread(
                _charge_saved_sync, amount_kopecks, idempotency_key, description, metadata,
                user_email, payment_method_id,
            ),
            timeout=10.0,
        )
    except asyncio.TimeoutError as exc:
        logger.error("yookassa_timeout", user_id=str(user_id), kind="subscription_renewal")
        raise ExternalServiceError("YooKassa timeout") from exc
