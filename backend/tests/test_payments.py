import hashlib
import hmac
import json

import pytest
from httpx import AsyncClient
from sqlalchemy import select

from app.core.config import settings
from app.core.db import SessionLocal
from app.domain.models import Event, EventStatus, Payment, PaymentStatus
from tests.helpers import auth_headers, authenticate, future_event_payload


def _sign(body: bytes) -> str:
    digest = hmac.new(
        settings.YOOKASSA_WEBHOOK_SECRET.get_secret_value().encode(),
        body,
        hashlib.sha256,
    ).hexdigest()
    return f"sha256={digest}"


@pytest.mark.asyncio
async def test_checkout_creates_pending_payment(client: AsyncClient) -> None:
    token = await authenticate(client)
    created = await client.post(
        "/api/v1/events/", json=future_event_payload(), headers=auth_headers(token)
    )
    event_id = created.json()["id"]

    resp = await client.post(
        f"/api/v1/events/{event_id}/checkout",
        json={"plan": "p50"},
        headers={**auth_headers(token), "Idempotency-Key": "key-1"},
    )
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["amount_kopecks"] == 99000
    assert body["confirmation_url"].startswith("http")

    async with SessionLocal() as s:
        pay = (await s.execute(select(Payment))).scalar_one()
        assert pay.status == PaymentStatus.PENDING
        assert pay.idempotency_key == "key-1"


@pytest.mark.asyncio
async def test_checkout_idempotent_on_repeat(client: AsyncClient) -> None:
    token = await authenticate(client)
    created = await client.post(
        "/api/v1/events/", json=future_event_payload(), headers=auth_headers(token)
    )
    event_id = created.json()["id"]
    headers = {**auth_headers(token), "Idempotency-Key": "key-x"}

    first = await client.post(
        f"/api/v1/events/{event_id}/checkout", json={"plan": "p10"}, headers=headers
    )
    second = await client.post(
        f"/api/v1/events/{event_id}/checkout", json={"plan": "p10"}, headers=headers
    )
    assert first.status_code == 200
    assert second.status_code == 200
    assert first.json()["payment_id"] == second.json()["payment_id"]


@pytest.mark.asyncio
async def test_checkout_free_plan_rejected(client: AsyncClient) -> None:
    token = await authenticate(client)
    created = await client.post(
        "/api/v1/events/", json=future_event_payload(), headers=auth_headers(token)
    )
    event_id = created.json()["id"]
    resp = await client.post(
        f"/api/v1/events/{event_id}/checkout",
        json={"plan": "free"},
        headers={**auth_headers(token), "Idempotency-Key": "k"},
    )
    assert resp.status_code == 409


@pytest.mark.asyncio
async def test_webhook_succeeded_activates_event(client: AsyncClient) -> None:
    token = await authenticate(client)
    created = await client.post(
        "/api/v1/events/", json=future_event_payload(), headers=auth_headers(token)
    )
    event_id = created.json()["id"]
    checkout = await client.post(
        f"/api/v1/events/{event_id}/checkout",
        json={"plan": "p50"},
        headers={**auth_headers(token), "Idempotency-Key": "k1"},
    )
    yk_id = checkout.json()["yookassa_id"]

    payload = {
        "event": "payment.succeeded",
        "object": {
            "id": yk_id,
            "status": "succeeded",
            "amount": {"value": "990.00", "currency": "RUB"},
        },
    }
    body = json.dumps(payload).encode()

    resp = await client.post(
        "/api/v1/webhooks/yookassa",
        content=body,
        headers={"Content-Type": "application/json", "X-Webhook-Signature": _sign(body)},
    )
    assert resp.status_code == 200, resp.text

    async with SessionLocal() as s:
        event = (await s.execute(select(Event).where(Event.id == event_id))).scalar_one()
        payment = (await s.execute(select(Payment))).scalar_one()
        assert event.status == EventStatus.ACTIVE
        assert payment.status == PaymentStatus.SUCCEEDED


@pytest.mark.asyncio
async def test_webhook_rejected_with_wrong_signature(client: AsyncClient) -> None:
    payload = b'{"event":"payment.succeeded","object":{"id":"x","status":"succeeded"}}'
    resp = await client.post(
        "/api/v1/webhooks/yookassa",
        content=payload,
        headers={"X-Webhook-Signature": "sha256=deadbeef"},
    )
    assert resp.status_code == 401


@pytest.mark.asyncio
async def test_webhook_unknown_payment_returns_ok(client: AsyncClient) -> None:
    payload = {"event": "payment.succeeded", "object": {"id": "unknown_x", "status": "succeeded"}}
    body = json.dumps(payload).encode()
    resp = await client.post(
        "/api/v1/webhooks/yookassa",
        content=body,
        headers={"X-Webhook-Signature": _sign(body)},
    )
    assert resp.status_code == 200
