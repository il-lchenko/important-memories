from uuid import UUID, uuid4

from fastapi import APIRouter

from app.api.deps import CurrentUserId, SessionDep
from app.domain.schemas.payments import (
    CheckoutIn,
    CheckoutOut,
    ExtendIn,
    ExtendOut,
    UpgradeIn,
    UpgradeOut,
)
from app.services import payment_service

router = APIRouter()


@router.post("/events/{event_id}/checkout", response_model=CheckoutOut)
async def create_checkout(
    event_id: UUID,
    body: CheckoutIn,
    session: SessionDep,
    user_id: CurrentUserId,
) -> CheckoutOut:
    """Initial plan purchase for a DRAFT event. Returns YooKassa confirmation URL."""
    idempotency_key = f"checkout:{event_id}:{body.plan.value}"
    return await payment_service.create_checkout(
        session=session,
        user_id=user_id,
        event_id=event_id,
        plan=body.plan,
        idempotency_key=idempotency_key,
    )


@router.post("/events/{event_id}/extend", response_model=ExtendOut)
async def extend_storage(
    event_id: UUID,
    body: ExtendIn,
    session: SessionDep,
    user_id: CurrentUserId,
) -> ExtendOut:
    """Purchase storage extension (+3m / +6m / +1y) for an ACTIVE or COMPLETED event."""
    idempotency_key = f"extend:{event_id}:{body.period}:{uuid4().hex[:8]}"
    return await payment_service.create_extend_checkout(
        session=session,
        user_id=user_id,
        event_id=event_id,
        period=body.period,
        idempotency_key=idempotency_key,
    )


@router.post("/events/{event_id}/upgrade", response_model=UpgradeOut)
async def upgrade_event(
    event_id: UUID,
    body: UpgradeIn,
    session: SessionDep,
    user_id: CurrentUserId,
) -> UpgradeOut:
    """Upgrade an ACTIVE event: kind='guests' (next tier) or kind='frames' (30→45)."""
    idempotency_key = f"upgrade:{event_id}:{body.kind}:{uuid4().hex[:8]}"
    return await payment_service.create_upgrade_checkout(
        session=session,
        user_id=user_id,
        event_id=event_id,
        kind=body.kind,
        idempotency_key=idempotency_key,
    )
