import json
from datetime import datetime, timedelta, timezone

import pytest
from httpx import AsyncClient
from sqlalchemy import select, update

from app.core.config import settings
from app.core.db import SessionLocal
from app.domain.models import Event, Payment, PaymentStatus, Subscription, SubscriptionStatus
from app.services import subscription_service
from tests.helpers import auth_headers, authenticate, future_event_payload


@pytest.fixture(autouse=True)
def _enable_subscription(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(settings, "SUBSCRIPTION_ENABLED", True)


async def _webhook(client: AsyncClient, event: str, yk_id: str, status: str, amount: str, saved: bool = True) -> None:
    payload = {
        "event": event,
        "object": {
            "id": yk_id,
            "status": status,
            "amount": {"value": amount, "currency": "RUB"},
            "payment_method": {"id": "pm-test-1", "saved": saved},
        },
    }
    resp = await client.post(
        "/api/v1/webhooks/yookassa", content=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json"},
    )
    assert resp.status_code == 200, resp.text


async def _subscribe(client: AsyncClient, token: str, period: str = "month", key: str = "sub-1") -> None:
    resp = await client.post(
        "/api/v1/subscription/checkout", json={"period": period},
        headers={**auth_headers(token), "Idempotency-Key": key},
    )
    assert resp.status_code == 200, resp.text
    async with SessionLocal() as s:
        payment = (await s.execute(select(Payment).where(Payment.idempotency_key == key))).scalar_one()
    amount = f"{payment.amount_kopecks / 100:.2f}"
    await _webhook(client, "payment.succeeded", payment.yookassa_id, "succeeded", amount)


async def _sub() -> Subscription:
    async with SessionLocal() as s:
        return (await s.execute(select(Subscription))).scalar_one()


@pytest.mark.asyncio
async def test_checkout_rejected_while_subscription_disabled(client: AsyncClient, monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(settings, "SUBSCRIPTION_ENABLED", False)
    token = await authenticate(client)
    resp = await client.post(
        "/api/v1/subscription/checkout", json={"period": "month"},
        headers={**auth_headers(token), "Idempotency-Key": "off-1"},
    )
    assert resp.status_code == 409


@pytest.mark.asyncio
async def test_checkout_creates_payment_without_event_and_webhook_activates_plus(client: AsyncClient) -> None:
    token = await authenticate(client)
    await _subscribe(client, token)

    async with SessionLocal() as s:
        payment = (await s.execute(select(Payment))).scalar_one()
        assert payment.event_id is None
        assert payment.amount_kopecks == 22900
        assert payment.status == PaymentStatus.SUCCEEDED
    sub = await _sub()
    assert sub.status == SubscriptionStatus.ACTIVE.value
    assert sub.payment_method_id == "pm-test-1"
    left = sub.current_period_end - datetime.now(timezone.utc)
    assert timedelta(days=29) < left <= timedelta(days=30, minutes=1)

    status = (await client.get("/api/v1/me/subscription", headers=auth_headers(token))).json()
    assert status["plus"] is True and status["enabled"] is True
    ent = (await client.get("/api/v1/me/entitlements", headers=auth_headers(token))).json()
    assert ent["plus"] is True and ent["tier"] == "subscription"
    assert ent["solo_frames_per_month"] == settings.SOLO_PLUS_FRAMES_PER_MONTH
    assert ent["mini_albums_limit"] is None
    assert ent["mini_frames_per_album"] == settings.MINI_PLUS_FRAMES_PER_ALBUM


@pytest.mark.asyncio
async def test_yearly_price_and_double_subscribe_blocked(client: AsyncClient) -> None:
    token = await authenticate(client)
    await _subscribe(client, token, period="year", key="year-1")
    async with SessionLocal() as s:
        payment = (await s.execute(select(Payment))).scalar_one()
        assert payment.amount_kopecks == 219000
    again = await client.post(
        "/api/v1/subscription/checkout", json={"period": "month"},
        headers={**auth_headers(token), "Idempotency-Key": "year-2"},
    )
    assert again.status_code == 409


@pytest.mark.asyncio
async def test_cancel_keeps_access_until_period_end_and_resume(client: AsyncClient) -> None:
    token = await authenticate(client)
    await _subscribe(client, token)
    cancelled = await client.post("/api/v1/subscription/cancel", headers=auth_headers(token))
    assert cancelled.status_code == 200
    assert cancelled.json()["cancel_at_period_end"] is True and cancelled.json()["plus"] is True
    resumed = await client.post("/api/v1/subscription/resume", headers=auth_headers(token))
    assert resumed.json()["cancel_at_period_end"] is False


@pytest.mark.asyncio
async def test_renewal_charges_saved_method_and_extends_period(client: AsyncClient) -> None:
    token = await authenticate(client)
    await _subscribe(client, token)
    old_end = datetime.now(timezone.utc) + timedelta(hours=12)
    async with SessionLocal() as s:
        await s.execute(update(Subscription).values(current_period_end=old_end))
        await s.commit()

    async with SessionLocal() as s:
        stats = await subscription_service.renew_due(s)
    assert stats["charged"] == 1

    async with SessionLocal() as s:
        renewal = (await s.execute(select(Payment).where(Payment.status == PaymentStatus.PENDING))).scalar_one()
        assert renewal.meta["renewal"] is True and renewal.event_id is None
    await _webhook(client, "payment.succeeded", renewal.yookassa_id, "succeeded", "229.00")

    sub = await _sub()
    assert abs((sub.current_period_end - (old_end + timedelta(days=30))).total_seconds()) < 5

    async with SessionLocal() as s:
        again = await subscription_service.renew_due(s)
    assert again["charged"] == 0


@pytest.mark.asyncio
async def test_failed_renewal_schedules_retry_and_access_remains_until_end(client: AsyncClient) -> None:
    token = await authenticate(client)
    await _subscribe(client, token)
    async with SessionLocal() as s:
        await s.execute(update(Subscription).values(current_period_end=datetime.now(timezone.utc) + timedelta(hours=12)))
        await s.commit()
    async with SessionLocal() as s:
        await subscription_service.renew_due(s)
        renewal = (await s.execute(select(Payment).where(Payment.status == PaymentStatus.PENDING))).scalar_one()
    await _webhook(client, "payment.canceled", renewal.yookassa_id, "canceled", "229.00")

    sub = await _sub()
    assert sub.status == SubscriptionStatus.PAST_DUE.value
    assert sub.retry_count == 1 and sub.next_retry_at is not None
    status = (await client.get("/api/v1/me/subscription", headers=auth_headers(token))).json()
    assert status["plus"] is True


@pytest.mark.asyncio
async def test_expired_subscription_removes_plus_and_shortens_solo_retention(client: AsyncClient) -> None:
    token = await authenticate(client)
    await _subscribe(client, token)
    solo = (await client.post("/api/v1/events/solo", json={"title": "Год"}, headers=auth_headers(token))).json()
    assert datetime.fromisoformat(solo["expires_at"]) - datetime.now(timezone.utc) > timedelta(days=300)

    async with SessionLocal() as s:
        await s.execute(update(Subscription).values(current_period_end=datetime.now(timezone.utc) - timedelta(minutes=1), cancel_at_period_end=True))
        await s.commit()
    async with SessionLocal() as s:
        stats = await subscription_service.renew_due(s)
    assert stats["expired"] == 1

    assert (await _sub()).status == SubscriptionStatus.CANCELLED.value
    status = (await client.get("/api/v1/me/subscription", headers=auth_headers(token))).json()
    assert status["plus"] is False
    async with SessionLocal() as s:
        event = (await s.execute(select(Event))).scalar_one()
        assert event.expires_at - datetime.now(timezone.utc) <= timedelta(days=30, minutes=1)


@pytest.mark.asyncio
async def test_extra_styles_require_plus_but_existing_choice_is_kept(client: AsyncClient) -> None:
    token = await authenticate(client)
    created = await client.post("/api/v1/events/", json=future_event_payload(), headers=auth_headers(token))
    event_id = created.json()["id"]

    free_ok = await client.patch(f"/api/v1/events/{event_id}/settings", json={"qr_style": "classic", "title_font": "playfair"}, headers=auth_headers(token))
    assert free_ok.status_code == 200, free_ok.text
    blocked = await client.patch(f"/api/v1/events/{event_id}/settings", json={"qr_style": "dark"}, headers=auth_headers(token))
    assert blocked.status_code == 403
    blocked_font = await client.patch(f"/api/v1/events/{event_id}/settings", json={"title_font": "caveat"}, headers=auth_headers(token))
    assert blocked_font.status_code == 403

    await _subscribe(client, token)
    paid_ok = await client.patch(f"/api/v1/events/{event_id}/settings", json={"qr_style": "dark", "title_font": "caveat"}, headers=auth_headers(token))
    assert paid_ok.status_code == 200, paid_ok.text

    async with SessionLocal() as s:
        await s.execute(update(Subscription).values(current_period_end=datetime.now(timezone.utc) - timedelta(minutes=1)))
        await s.commit()
    kept = await client.patch(f"/api/v1/events/{event_id}/settings", json={"qr_style": "dark"}, headers=auth_headers(token))
    assert kept.status_code == 200, kept.text


@pytest.mark.asyncio
async def test_refund_ends_subscription(client: AsyncClient) -> None:
    token = await authenticate(client)
    await _subscribe(client, token)
    async with SessionLocal() as s:
        payment = (await s.execute(select(Payment))).scalar_one()
    payload = {"event": "refund.succeeded", "object": {"id": "refund-1", "payment_id": payment.yookassa_id, "amount": {"value": "229.00", "currency": "RUB"}}}
    resp = await client.post("/api/v1/webhooks/yookassa", content=json.dumps(payload).encode(), headers={"Content-Type": "application/json"})
    assert resp.status_code == 200
    status = (await client.get("/api/v1/me/subscription", headers=auth_headers(token))).json()
    assert status["plus"] is False
