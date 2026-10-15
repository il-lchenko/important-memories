import json

import pytest
from httpx import AsyncClient
from sqlalchemy import select

from app.core.db import SessionLocal
from app.domain.models import (
    Event,
    EventStatus,
    Payment,
    PaymentStatus,
    Promocode,
    PromocodeDiscountType,
    PromocodeKind,
    PromocodeRedemption,
    User,
)
from app.infra import yookassa_client
from tests.helpers import auth_headers, authenticate, future_event_payload


async def _create_event(client: AsyncClient, token: str, **extra) -> str:
    resp = await client.post(
        "/api/v1/events/",
        json={**future_event_payload(), **extra},
        headers=auth_headers(token),
    )
    assert resp.status_code == 201, resp.text
    return resp.json()["id"]


async def _checkout(client: AsyncClient, token: str, event_id: str, plan: str, **extra) -> dict:
    resp = await client.post(
        f"/api/v1/events/{event_id}/checkout",
        json={"plan": plan, **extra},
        headers={**auth_headers(token), "Idempotency-Key": f"k-{event_id}-{plan}"},
    )
    assert resp.status_code == 200, resp.text
    return resp.json()


async def _webhook(client: AsyncClient, event: str, obj: dict) -> None:
    resp = await client.post(
        "/api/v1/webhooks/yookassa",
        content=json.dumps({"event": event, "object": obj}).encode(),
        headers={"Content-Type": "application/json"},
    )
    assert resp.status_code == 200, resp.text


async def _load_event(event_id: str) -> Event:
    async with SessionLocal() as s:
        return (await s.execute(select(Event).where(Event.id == event_id))).scalar_one()


async def _get_event(client: AsyncClient, token: str, event_id: str) -> dict:
    resp = await client.get(f"/api/v1/events/{event_id}", headers=auth_headers(token))
    assert resp.status_code == 200, resp.text
    return resp.json()


@pytest.mark.asyncio
async def test_activate_paid_plan_without_payment_forbidden(client: AsyncClient) -> None:
    token = await authenticate(client)
    event_id = await _create_event(client, token, plan="p250")
    resp = await client.post(f"/api/v1/events/{event_id}/activate", headers=auth_headers(token))
    assert resp.status_code == 403
    assert (await _load_event(event_id)).status == EventStatus.DRAFT


@pytest.mark.asyncio
async def test_admin_can_activate_paid_plan(client: AsyncClient) -> None:
    token = await authenticate(client, "admin@example.com")
    async with SessionLocal() as s:
        user = (await s.execute(select(User).where(User.email == "admin@example.com"))).scalar_one()
        user.is_admin = True
        await s.commit()
    event_id = await _create_event(client, token, plan="p50")
    resp = await client.post(f"/api/v1/events/{event_id}/activate", headers=auth_headers(token))
    assert resp.status_code == 200, resp.text
    assert resp.json()["settings"]["plan"] == "p50"


@pytest.mark.asyncio
async def test_plan_change_on_active_event_rejected(client: AsyncClient) -> None:
    token = await authenticate(client)
    event_id = await _create_event(client, token)
    await client.post(f"/api/v1/events/{event_id}/activate", headers=auth_headers(token))
    resp = await client.patch(
        f"/api/v1/events/{event_id}/settings",
        json={"plan": "p250"},
        headers=auth_headers(token),
    )
    assert resp.status_code == 409
    assert (await _get_event(client, token, event_id))["settings"]["max_guests"] == 5


@pytest.mark.asyncio
async def test_custom_plan_checkout_returns_conflict(client: AsyncClient) -> None:
    token = await authenticate(client)
    event_id = await _create_event(client, token)
    resp = await client.post(
        f"/api/v1/events/{event_id}/checkout",
        json={"plan": "custom"},
        headers={**auth_headers(token), "Idempotency-Key": "custom-1"},
    )
    assert resp.status_code == 409


@pytest.mark.asyncio
async def test_webhook_applies_plan_from_payment_meta(client: AsyncClient) -> None:
    token = await authenticate(client)
    event_id = await _create_event(client, token)
    checkout = await _checkout(client, token, event_id, "p50")
    await client.patch(
        f"/api/v1/events/{event_id}/settings",
        json={"plan": "p10"},
        headers=auth_headers(token),
    )

    await _webhook(client, "payment.succeeded", {
        "id": checkout["yookassa_id"],
        "status": "succeeded",
        "amount": {"value": "1290.00", "currency": "RUB"},
    })

    event = await _get_event(client, token, event_id)
    assert event["status"] == "active"
    assert event["settings"]["plan"] == "p50"
    assert event["settings"]["max_guests"] == 50


@pytest.mark.asyncio
async def test_webhook_not_applied_when_api_disagrees(
    client: AsyncClient, monkeypatch: pytest.MonkeyPatch
) -> None:
    token = await authenticate(client)
    event_id = await _create_event(client, token)
    checkout = await _checkout(client, token, event_id, "p50")

    async def fake_fetch(yookassa_id: str) -> yookassa_client.YookassaPaymentInfo:
        return yookassa_client.YookassaPaymentInfo(
            id=yookassa_id, status="pending", amount_kopecks=129000, refunded_kopecks=0,
        )

    monkeypatch.setattr(yookassa_client, "is_configured", lambda: True)
    monkeypatch.setattr(yookassa_client, "fetch_payment", fake_fetch)

    await _webhook(client, "payment.succeeded", {
        "id": checkout["yookassa_id"],
        "status": "succeeded",
        "amount": {"value": "1290.00", "currency": "RUB"},
    })

    assert (await _load_event(event_id)).status == EventStatus.DRAFT
    async with SessionLocal() as s:
        payment = (await s.execute(select(Payment))).scalar_one()
        assert payment.status == PaymentStatus.PENDING


@pytest.mark.asyncio
async def test_cancelled_payment_releases_promocode(client: AsyncClient) -> None:
    token = await authenticate(client)
    async with SessionLocal() as s:
        promo = Promocode(
            code="SALE10",
            kind=PromocodeKind.MANUAL,
            discount_type=PromocodeDiscountType.PERCENT,
            discount_value=10,
        )
        s.add(promo)
        await s.commit()

    event_id = await _create_event(client, token)
    checkout = await _checkout(client, token, event_id, "p50", promocode="SALE10")

    await _webhook(client, "payment.canceled", {"id": checkout["yookassa_id"], "status": "canceled"})

    async with SessionLocal() as s:
        promo = (await s.execute(select(Promocode).where(Promocode.code == "SALE10"))).scalar_one()
        assert promo.redemptions_count == 0
        assert (await s.execute(select(PromocodeRedemption))).first() is None
        payment = (await s.execute(select(Payment))).scalar_one()
        assert payment.status == PaymentStatus.CANCELLED


@pytest.mark.asyncio
async def test_refund_succeeded_reverts_checkout(client: AsyncClient) -> None:
    token = await authenticate(client)
    event_id = await _create_event(client, token)
    checkout = await _checkout(client, token, event_id, "p50")
    await _webhook(client, "payment.succeeded", {
        "id": checkout["yookassa_id"],
        "status": "succeeded",
        "amount": {"value": "1290.00", "currency": "RUB"},
    })

    await _webhook(client, "refund.succeeded", {
        "id": "refund-1",
        "payment_id": checkout["yookassa_id"],
        "status": "succeeded",
        "amount": {"value": "1290.00", "currency": "RUB"},
    })

    async with SessionLocal() as s:
        payment = (await s.execute(select(Payment))).scalar_one()
        assert payment.status == PaymentStatus.REFUNDED
    event = await _get_event(client, token, event_id)
    assert event["status"] == "draft"
    assert event["settings"]["plan"] == "free"


@pytest.mark.asyncio
async def test_late_webhook_upgrades_already_active_event(client: AsyncClient) -> None:
    token = await authenticate(client)
    event_id = await _create_event(client, token)
    checkout = await _checkout(client, token, event_id, "p50")
    await client.patch(
        f"/api/v1/events/{event_id}/settings",
        json={"plan": "free"},
        headers=auth_headers(token),
    )
    activated = await client.post(f"/api/v1/events/{event_id}/activate", headers=auth_headers(token))
    assert activated.status_code == 200

    await _webhook(client, "payment.succeeded", {
        "id": checkout["yookassa_id"],
        "status": "succeeded",
        "amount": {"value": "1290.00", "currency": "RUB"},
    })

    assert (await _get_event(client, token, event_id))["settings"]["max_guests"] == 50
