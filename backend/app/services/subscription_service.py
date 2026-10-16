"""Подписка «Плюс»: оформление, продление автосписанием, отмена.

Жизненный цикл:
1. Первый платёж идёт через YooKassa с сохранением способа оплаты; webhook создаёт подписку.
2. За сутки до конца периода cron списывает следующий период с сохранённого способа.
3. Неудачное списание повторяется (через 1, 3 и 5 дней); если период закончился и
   списать не удалось, подписка истекает.
4. Отмена выключает автосписание; доступ остаётся до конца оплаченного периода.
5. После окончания подписки соло-альбомам даётся 30 дней на скачивание.
"""
from datetime import datetime, timedelta, timezone
from uuid import UUID

from sqlalchemy import select, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.core.errors import ConflictError, NotFoundError
from app.core.logging import logger
from app.domain.models import (
    Event,
    EventKind,
    EventStatus,
    Payment,
    PaymentStatus,
    Subscription,
    SubscriptionStatus,
)
from app.domain.schemas.subscription import SubscriptionCheckoutOut, SubscriptionOut
from app.infra import yookassa_client
from app.repos import payment_repo, user_repo
from app.services import entitlement_service

_PERIOD_DAYS = {"month": 30, "year": 365}
_RETRY_DELAYS_DAYS = (1, 3, 5)
_RENEW_AHEAD = timedelta(days=1)


def price_kopecks(period: str) -> int:
    return settings.SUB_PRICE_YEAR_KOPECKS if period == "year" else settings.SUB_PRICE_MONTH_KOPECKS


def _now() -> datetime:
    return datetime.now(timezone.utc)


async def _get(session: AsyncSession, user_id: UUID) -> Subscription | None:
    return (await session.execute(select(Subscription).where(Subscription.user_id == user_id))).scalar_one_or_none()


def _to_out(sub: Subscription | None, plus: bool) -> SubscriptionOut:
    return SubscriptionOut(
        enabled=settings.SUBSCRIPTION_ENABLED,
        plus=plus,
        status=sub.status if sub else None,
        period=sub.period if sub else None,
        current_period_end=sub.current_period_end if sub else None,
        cancel_at_period_end=sub.cancel_at_period_end if sub else False,
        month_kopecks=settings.SUB_PRICE_MONTH_KOPECKS,
        year_kopecks=settings.SUB_PRICE_YEAR_KOPECKS,
    )


async def get_status(session: AsyncSession, user_id: UUID) -> SubscriptionOut:
    user = await user_repo.get_by_id(session, user_id)
    if user is None:
        raise NotFoundError("User not found")
    sub = await _get(session, user_id)
    return _to_out(sub, await entitlement_service.has_plus(session, user))


async def create_checkout(
    session: AsyncSession,
    user_id: UUID,
    period: str,
    idempotency_key: str,
    payment_method: str | None = None,
) -> SubscriptionCheckoutOut:
    if not settings.SUBSCRIPTION_ENABLED:
        raise ConflictError("Подписка пока не запущена", details={"reason": "subscription_disabled"})
    if period not in _PERIOD_DAYS:
        raise ConflictError("Неизвестный период подписки", details={"period": period})
    user = await user_repo.get_by_id(session, user_id)
    if user is None:
        raise NotFoundError("User not found")

    existing = await payment_repo.get_by_idempotency_key(session, idempotency_key)
    if existing is not None:
        return SubscriptionCheckoutOut(
            payment_id=existing.id,
            confirmation_url=existing.meta.get("confirmation_url", ""),
            amount_kopecks=existing.amount_kopecks,
        )

    if await entitlement_service.has_plus(session, user):
        sub = await _get(session, user_id)
        if sub is not None and not sub.cancel_at_period_end:
            raise ConflictError("Подписка уже оформлена", details={"reason": "already_subscribed"})

    amount = price_kopecks(period)
    yk = await yookassa_client.create_subscription_payment(
        user_id=user_id, period=period, amount_kopecks=amount,
        idempotency_key=idempotency_key, user_email=user.email, payment_method=payment_method,
    )
    payment = Payment(
        event_id=None,
        user_id=user_id,
        yookassa_id=yk.id,
        amount_kopecks=amount,
        status=PaymentStatus.PENDING,
        idempotency_key=idempotency_key,
        meta={"kind": "subscription", "period": period, "confirmation_url": yk.confirmation_url},
    )
    await payment_repo.create(session, payment)
    await session.commit()
    return SubscriptionCheckoutOut(
        payment_id=payment.id, confirmation_url=yk.confirmation_url, amount_kopecks=amount
    )


async def apply_succeeded_payment(
    session: AsyncSession, payment: Payment, payment_method_id: str | None
) -> None:
    """Webhook: платёж подписки прошёл. Создаёт подписку или продлевает период."""
    period = payment.meta.get("period", "month")
    days = _PERIOD_DAYS.get(period, 30)
    now = _now()
    sub = await _get(session, payment.user_id)
    if sub is None:
        sub = Subscription(
            user_id=payment.user_id,
            status=SubscriptionStatus.ACTIVE.value,
            period=period,
            payment_method_id=payment_method_id,
            current_period_start=now,
            current_period_end=now + timedelta(days=days),
        )
        session.add(sub)
    else:
        base = sub.current_period_end if sub.current_period_end > now else now
        sub.period = period
        sub.status = SubscriptionStatus.ACTIVE.value
        sub.current_period_start = base if sub.current_period_end > now else now
        sub.current_period_end = base + timedelta(days=days)
        sub.cancel_at_period_end = False
        sub.retry_count = 0
        sub.next_retry_at = None
        if payment_method_id:
            sub.payment_method_id = payment_method_id
    await _extend_solo_retention(session, payment.user_id)
    logger.info("subscription_period_paid", user_id=str(payment.user_id), period=period)


async def apply_failed_payment(session: AsyncSession, payment: Payment) -> None:
    """Webhook: списание за период отменено банком. Планируем повтор."""
    sub = await _get(session, payment.user_id)
    if sub is None or not payment.meta.get("renewal"):
        return
    await _schedule_retry(sub)


async def apply_refund(session: AsyncSession, payment: Payment) -> None:
    """Возврат платежа подписки: доступ заканчивается, автосписание выключено."""
    sub = await _get(session, payment.user_id)
    if sub is None:
        return
    sub.status = SubscriptionStatus.CANCELLED.value
    sub.current_period_end = _now()
    sub.cancel_at_period_end = True
    await _shorten_solo_retention(session, payment.user_id)


async def cancel(session: AsyncSession, user_id: UUID) -> SubscriptionOut:
    sub = await _get(session, user_id)
    if sub is None or sub.status not in (SubscriptionStatus.ACTIVE.value, SubscriptionStatus.PAST_DUE.value):
        raise ConflictError("Нет активной подписки", details={"reason": "no_subscription"})
    sub.cancel_at_period_end = True
    await session.commit()
    return await get_status(session, user_id)


async def resume(session: AsyncSession, user_id: UUID) -> SubscriptionOut:
    sub = await _get(session, user_id)
    if sub is None or sub.status != SubscriptionStatus.ACTIVE.value or sub.current_period_end <= _now():
        raise ConflictError("Нечего возобновлять", details={"reason": "not_resumable"})
    sub.cancel_at_period_end = False
    await session.commit()
    return await get_status(session, user_id)


async def _schedule_retry(sub: Subscription) -> None:
    sub.retry_count += 1
    sub.status = SubscriptionStatus.PAST_DUE.value
    if sub.retry_count <= len(_RETRY_DELAYS_DAYS):
        sub.next_retry_at = _now() + timedelta(days=_RETRY_DELAYS_DAYS[sub.retry_count - 1])
    else:
        sub.next_retry_at = None


async def _extend_solo_retention(session: AsyncSession, user_id: UUID) -> None:
    """Подписка началась: соло-альбомы живут, пока она действует."""
    horizon = _now() + timedelta(days=settings.SOLO_PLUS_RETENTION_DAYS)
    await session.execute(
        update(Event)
        .where(
            Event.user_id == user_id,
            Event.kind == EventKind.SOLO.value,
            Event.status != EventStatus.CANCELLED,
            Event.storage_purged_at.is_(None),
            Event.expires_at.is_not(None),
            Event.expires_at < horizon,
        )
        .values(expires_at=horizon)
    )


async def _shorten_solo_retention(session: AsyncSession, user_id: UUID) -> None:
    """Подписка закончилась. Каждому соло-альбому оставляем не меньше SOLO_GRACE_DAYS на
    скачивание и не меньше обычного бесплатного срока от его создания, чтобы подписка не
    отнимала то, что и так положено бесплатно."""
    now = _now()
    grace = now + timedelta(days=settings.SOLO_GRACE_DAYS)
    events = (
        await session.execute(
            select(Event).where(
                Event.user_id == user_id,
                Event.kind == EventKind.SOLO.value,
                Event.status != EventStatus.CANCELLED,
                Event.storage_purged_at.is_(None),
            )
        )
    ).scalars().all()
    for ev in events:
        free_until = ev.created_at + timedelta(days=settings.SOLO_FREE_RETENTION_DAYS)
        deadline = max(grace, free_until)
        if ev.expires_at is None or ev.expires_at > deadline:
            ev.expires_at = deadline


async def renew_due(session: AsyncSession) -> dict[str, int]:
    """Cron: списывает следующий период, повторяет неудачные, закрывает истёкшие."""
    now = _now()
    stats = {"charged": 0, "failed": 0, "expired": 0}

    due = (
        await session.execute(
            select(Subscription).where(
                Subscription.status.in_((SubscriptionStatus.ACTIVE.value, SubscriptionStatus.PAST_DUE.value)),
                Subscription.cancel_at_period_end.is_(False),
                Subscription.current_period_end <= now + _RENEW_AHEAD,
                Subscription.payment_method_id.is_not(None),
            )
        )
    ).scalars().all()

    for sub in due:
        if sub.next_retry_at is not None and sub.next_retry_at > now:
            continue
        if sub.retry_count > len(_RETRY_DELAYS_DAYS):
            continue
        user = await user_repo.get_by_id(session, sub.user_id)
        if user is None:
            continue
        amount = price_kopecks(sub.period)
        key = f"sub_{sub.id.hex[:12]}_{int(sub.current_period_end.timestamp())}_{sub.retry_count}"[:64]
        if await payment_repo.get_by_idempotency_key(session, key) is not None:
            continue
        try:
            yk = await yookassa_client.charge_saved_method(
                user_id=sub.user_id, period=sub.period, amount_kopecks=amount,
                idempotency_key=key, user_email=user.email, payment_method_id=sub.payment_method_id,
            )
        except Exception:
            logger.warning("subscription_charge_failed", user_id=str(sub.user_id))
            await _schedule_retry(sub)
            stats["failed"] += 1
            continue
        await payment_repo.create(
            session,
            Payment(
                event_id=None, user_id=sub.user_id, yookassa_id=yk.id, amount_kopecks=amount,
                status=PaymentStatus.PENDING, idempotency_key=key,
                meta={"kind": "subscription", "period": sub.period, "renewal": True},
            ),
        )
        stats["charged"] += 1
    await session.commit()

    finished = (
        await session.execute(
            select(Subscription).where(
                Subscription.status.in_((SubscriptionStatus.ACTIVE.value, SubscriptionStatus.PAST_DUE.value)),
                Subscription.current_period_end <= now,
            )
        )
    ).scalars().all()
    for sub in finished:
        sub.status = (
            SubscriptionStatus.CANCELLED.value if sub.cancel_at_period_end else SubscriptionStatus.EXPIRED.value
        )
        await _shorten_solo_retention(session, sub.user_id)
        stats["expired"] += 1
    await session.commit()
    return stats
