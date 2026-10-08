import secrets
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from uuid import UUID

from sqlalchemy.ext.asyncio import AsyncSession

from app.core.errors import ConflictError, NotFoundError
from app.core.logging import logger
from app.domain.models import (
    Promocode,
    PromocodeAppliesTo,
    PromocodeDiscountType,
    PromocodeKind,
    PromocodeRedemption,
    User,
)
from app.repos import promocode_repo, user_repo


_REF_ALPHABET = "23456789ABCDEFGHJKLMNPQRSTUVWXYZ"


def generate_referral_code() -> str:
    return "IM-" + "".join(secrets.choice(_REF_ALPHABET) for _ in range(6))


async def ensure_unique_referral_code(session: AsyncSession, user: User) -> str:
    """Генерирует уникальный код и сохраняет его user.referral_code (если его нет)."""
    if user.referral_code:
        return user.referral_code
    for _ in range(20):
        code = generate_referral_code()
        existing = await user_repo.get_by_referral_code(session, code)
        if existing is None:
            user.referral_code = code
            await session.flush()
            return code
    raise ConflictError("Could not generate unique referral code")


@dataclass
class PromocodeValidation:
    valid: bool
    discount_kopecks: int = 0
    promocode_id: UUID | None = None
    error: str | None = None


async def validate_promocode(
    session: AsyncSession,
    *,
    code: str,
    user_id: UUID,
    amount_kopecks: int,
    applies_to: str,
) -> PromocodeValidation:
    """Проверяет промокод без применения. applies_to: 'checkout'|'extend'|'upgrade'."""
    normalized = (code or "").strip().upper()
    if not normalized:
        return PromocodeValidation(valid=False, error="Пустой код")

    promo = await promocode_repo.get_by_code(session, normalized)
    if promo is None:
        return PromocodeValidation(valid=False, error="Промокод не найден")

    now = datetime.now(timezone.utc)
    if promo.expires_at is not None and promo.expires_at < now:
        return PromocodeValidation(valid=False, error="Срок промокода истёк")

    if promo.max_redemptions is not None and promo.redemptions_count >= promo.max_redemptions:
        return PromocodeValidation(valid=False, error="Промокод исчерпан")

    if promo.owner_user_id is not None and promo.owner_user_id != user_id:
        return PromocodeValidation(valid=False, error="Промокод не для вас")

    if promo.applies_to not in (PromocodeAppliesTo.ALL, PromocodeAppliesTo(applies_to)):
        return PromocodeValidation(valid=False, error="Промокод не подходит к этому действию")

    if amount_kopecks < promo.min_amount_kopecks:
        return PromocodeValidation(
            valid=False,
            error=f"Минимальная сумма: {promo.min_amount_kopecks // 100} ₽",
        )

    if promo.single_use_per_user:
        redemption = await promocode_repo.redemption_by_user(session, promo.id, user_id)
        if redemption is not None:
            return PromocodeValidation(valid=False, error="Вы уже использовали этот промокод")

    discount = _calculate_discount(promo, amount_kopecks)
    return PromocodeValidation(valid=True, discount_kopecks=discount, promocode_id=promo.id)


def _calculate_discount(promo: Promocode, amount_kopecks: int) -> int:
    if promo.discount_type == PromocodeDiscountType.PERCENT:
        discount = amount_kopecks * promo.discount_value // 100
    else:
        discount = promo.discount_value
    return min(discount, amount_kopecks)


async def apply_promocode(
    session: AsyncSession,
    *,
    promocode_id: UUID,
    user_id: UUID,
    payment_id: UUID | None,
    discount_kopecks: int,
) -> PromocodeRedemption:
    """Создаёт запись PromocodeRedemption и инкрементит счётчик промокода.

    Вызывается сразу после создания Payment (или в admin-bypass) — под тем же коммитом.
    """
    promo = await promocode_repo.get_by_id(session, promocode_id)
    if promo is None:
        raise NotFoundError("Promocode disappeared")
    promo.redemptions_count = promo.redemptions_count + 1

    redemption = PromocodeRedemption(
        promocode_id=promo.id,
        user_id=user_id,
        payment_id=payment_id,
        discount_applied_kopecks=discount_kopecks,
    )
    return await promocode_repo.create_redemption(session, redemption)


async def issue_referral_reward(
    session: AsyncSession,
    referrer_user_id: UUID,
    *,
    discount_percent: int = 20,
    valid_days: int = 90,
) -> Promocode:
    """Выпускает REFERRAL-промокод для пригласившего юзера.

    Вызывается когда приглашённый гость впервые сделал платный платёж.
    """
    code = f"REF-{secrets.token_hex(4).upper()}"
    promo = Promocode(
        code=code,
        kind=PromocodeKind.REFERRAL,
        discount_type=PromocodeDiscountType.PERCENT,
        discount_value=discount_percent,
        max_redemptions=1,
        redemptions_count=0,
        expires_at=datetime.now(timezone.utc) + timedelta(days=valid_days),
        applies_to=PromocodeAppliesTo.ALL,
        min_amount_kopecks=0,
        single_use_per_user=True,
        created_by_user_id=referrer_user_id,
        owner_user_id=referrer_user_id,
    )
    await promocode_repo.create(session, promo)
    logger.info(
        "referral_reward_issued",
        referrer_id=str(referrer_user_id),
        promocode_id=str(promo.id),
        discount_percent=discount_percent,
    )
    return promo


async def issue_welcome_bonus(
    session: AsyncSession,
    new_user_id: UUID,
    *,
    discount_percent: int = 20,
    valid_days: int = 90,
) -> Promocode:
    """Выпускает welcome-промокод новому юзеру (для приглашённых гостей).

    Пригласительная сторона double-sided reward — приглашённый получает скидку
    на первый CHECKOUT-платёж от P25 и выше.
    """
    code = f"WEL-{secrets.token_hex(4).upper()}"
    promo = Promocode(
        code=code,
        kind=PromocodeKind.REFERRAL,
        discount_type=PromocodeDiscountType.PERCENT,
        discount_value=discount_percent,
        max_redemptions=1,
        redemptions_count=0,
        expires_at=datetime.now(timezone.utc) + timedelta(days=valid_days),
        applies_to=PromocodeAppliesTo.CHECKOUT,
        min_amount_kopecks=44900,  # P25 и выше
        single_use_per_user=True,
        created_by_user_id=None,
        owner_user_id=new_user_id,
    )
    await promocode_repo.create(session, promo)
    logger.info(
        "welcome_bonus_issued",
        user_id=str(new_user_id),
        promocode_id=str(promo.id),
    )
    return promo
