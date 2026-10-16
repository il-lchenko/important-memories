from typing import Annotated

from fastapi import APIRouter, Header, HTTPException

from app.api.deps import CurrentUserId, SessionDep
from app.domain.schemas.subscription import (
    SubscriptionCheckoutIn,
    SubscriptionCheckoutOut,
    SubscriptionOut,
)
from app.services import subscription_service

router = APIRouter()


@router.get("/me/subscription", response_model=SubscriptionOut)
async def get_subscription(user_id: CurrentUserId, session: SessionDep) -> SubscriptionOut:
    return await subscription_service.get_status(session, user_id)


@router.post("/subscription/checkout", response_model=SubscriptionCheckoutOut)
async def subscription_checkout(
    payload: SubscriptionCheckoutIn,
    user_id: CurrentUserId,
    session: SessionDep,
    idempotency_key: Annotated[str | None, Header(alias="Idempotency-Key")] = None,
) -> SubscriptionCheckoutOut:
    if not idempotency_key:
        raise HTTPException(status_code=400, detail="Idempotency-Key header is required for payment endpoints")
    return await subscription_service.create_checkout(
        session, user_id, payload.period, idempotency_key, payload.payment_method
    )


@router.post("/subscription/cancel", response_model=SubscriptionOut)
async def subscription_cancel(user_id: CurrentUserId, session: SessionDep) -> SubscriptionOut:
    return await subscription_service.cancel(session, user_id)


@router.post("/subscription/resume", response_model=SubscriptionOut)
async def subscription_resume(user_id: CurrentUserId, session: SessionDep) -> SubscriptionOut:
    return await subscription_service.resume(session, user_id)
