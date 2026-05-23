import json
from typing import Annotated

from fastapi import APIRouter, Header, Request

from app.api.deps import SessionDep
from app.services import payment_service

router = APIRouter()


@router.post("/yookassa")
async def yookassa_webhook(
    request: Request,
    session: SessionDep,
    x_webhook_signature: Annotated[str | None, Header(alias="X-Webhook-Signature")] = None,
) -> dict[str, bool]:
    raw_body = await request.body()
    payment_service.verify_webhook_signature(raw_body, x_webhook_signature)
    payload = json.loads(raw_body)
    await payment_service.handle_webhook(session, payload)
    return {"ok": True}
