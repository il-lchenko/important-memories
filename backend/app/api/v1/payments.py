from fastapi import APIRouter

from app.api.deps import CurrentUserId, SessionDep
from app.core.errors import ConflictError, NotFoundError
from app.domain.models import Plan, PromocodeKind
from app.domain.schemas.promocodes import (
    PromocodeOut,
    ReferralStatsOut,
    ValidatePromocodeIn,
    ValidatePromocodeOut,
)
from app.repos import event_repo, promocode_repo, user_repo
from app.domain.schemas.payments import PricingOut
from app.services import payment_service, promocode_service
from app.services.payment_service import (
    EXTEND_OPTIONS,
    PLAN_PRICES_KOPECKS,
    extend_price_kopecks,
    frames_upgrade_price_per_guest_kopecks,
    _UPGRADE_GUESTS_PATH,
    _UPGRADE_PREMIUM,
)

router = APIRouter()


def _estimate_amount(event, kind: str, plan: str | None, period: str | None, upgrade_kind: str | None) -> int:
    """Оценивает сумму в копейках для preview скидки — без создания платежа."""
    if kind == "checkout":
        if plan:
            try:
                return PLAN_PRICES_KOPECKS[Plan(plan)]
            except (KeyError, ValueError):
                return 0
        if event is not None:
            return PLAN_PRICES_KOPECKS.get(event.settings.plan, 0)
        return 0
    if kind == "extend":
        chosen = period if period in EXTEND_OPTIONS else "6m"
        guests = event.settings.max_guests if event is not None else 0
        return extend_price_kopecks(chosen, guests)
    if kind == "upgrade" and event is not None:
        if upgrade_kind == "guests":
            current_plan = event.settings.plan
            next_plan = _UPGRADE_GUESTS_PATH.get(current_plan)
            if next_plan is None:
                return 0
            return int(
                (PLAN_PRICES_KOPECKS[next_plan] - PLAN_PRICES_KOPECKS[current_plan])
                * _UPGRADE_PREMIUM
            )
        if upgrade_kind == "frames":
            return event.settings.max_guests * frames_upgrade_price_per_guest_kopecks()
    return 0


@router.get("/pricing", response_model=PricingOut)
async def get_pricing() -> PricingOut:
    return payment_service.pricing_catalog()


@router.post("/promocodes/validate", response_model=ValidatePromocodeOut)
async def validate_promocode(
    payload: ValidatePromocodeIn,
    user_id: CurrentUserId,
    session: SessionDep,
) -> ValidatePromocodeOut:
    event = None
    if payload.event_id is not None:
        event = await event_repo.get_by_id(session, payload.event_id)

    original_amount = _estimate_amount(
        event, payload.kind, payload.plan, payload.period, payload.upgrade_kind
    )

    if original_amount <= 0:
        return ValidatePromocodeOut(
            valid=False,
            error="Невозможно применить промокод (нулевая сумма)",
        )

    result = await promocode_service.validate_promocode(
        session,
        code=payload.code,
        user_id=user_id,
        amount_kopecks=original_amount,
        applies_to=payload.kind,
    )
    return ValidatePromocodeOut(
        valid=result.valid,
        discount_kopecks=result.discount_kopecks,
        final_amount_kopecks=max(0, original_amount - result.discount_kopecks) if result.valid else None,
        original_amount_kopecks=original_amount,
        error=result.error,
    )


@router.get("/me/promocodes", response_model=list[PromocodeOut])
async def my_promocodes(
    user_id: CurrentUserId,
    session: SessionDep,
) -> list[PromocodeOut]:
    promos = await promocode_repo.list_active_for_user(session, user_id)
    return [PromocodeOut.model_validate(p) for p in promos]


@router.get("/me/referrals", response_model=ReferralStatsOut)
async def my_referrals(
    user_id: CurrentUserId,
    session: SessionDep,
) -> ReferralStatsOut:
    user = await user_repo.get_by_id(session, user_id)
    if user is None:
        raise NotFoundError("User not found")
    # Ленивая генерация — для юзеров, у которых код ещё не выдан.
    if user.referral_code is None:
        await promocode_service.ensure_unique_referral_code(session, user)
        await session.commit()

    referrals_count = await promocode_repo.count_referrals(session, user_id)
    total_earned = await promocode_repo.sum_referral_rewards(session, user_id)

    # Pending — REFERRAL промокоды принадлежащие юзеру и не полностью использованные.
    my_promos = await promocode_repo.list_active_for_user(session, user_id)
    pending = sum(
        1
        for p in my_promos
        if p.kind == PromocodeKind.REFERRAL
        and (p.max_redemptions is None or p.redemptions_count < p.max_redemptions)
    )

    return ReferralStatsOut(
        referral_code=user.referral_code,
        referrals_count=referrals_count,
        total_earned_kopecks=total_earned,
        pending_promocodes_count=pending,
    )
