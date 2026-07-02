import json

from fastapi import APIRouter, Request

from app.api.deps import SessionDep
from app.services import payment_service

router = APIRouter()


# NOTE (security): YooKassa does NOT sign webhook payloads with HMAC.
# We rely on nginx IP-whitelist (only YooKassa IPs allowed to reach this endpoint).
# See infra/nginx.conf → location = /api/v1/webhooks/yookassa.
@router.post("/yookassa")
async def yookassa_webhook(
    request: Request,
    session: SessionDep,
) -> dict[str, bool]:
    raw_body = await request.body()
    payload = json.loads(raw_body)
    await payment_service.handle_webhook(session, payload)
    return {"ok": True}
