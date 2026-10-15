from datetime import datetime, timedelta, timezone

import pytest
from httpx import AsyncClient

from app.core.config import settings
from app.domain.models import Event, EventStatus
from app.services import event_service, payment_service
from app.workers import storage_purge
from tests.helpers import auth_headers, authenticate, future_event_payload


async def _create_and_activate(client: AsyncClient, token: str):
    created = await client.post("/api/v1/events/", json=future_event_payload(), headers=auth_headers(token))
    event_id = created.json()["id"]
    return event_id, await client.post(f"/api/v1/events/{event_id}/activate", headers=auth_headers(token))


@pytest.mark.asyncio
async def test_free_active_limit_and_slot_release(client: AsyncClient, monkeypatch) -> None:
    monkeypatch.setattr(settings, "FREE_ACTIVE_EVENTS", 2)
    monkeypatch.setattr(settings, "FREE_EVENTS_PER_MONTH", 4)
    token = await authenticate(client)
    first, r1 = await _create_and_activate(client, token)
    _, r2 = await _create_and_activate(client, token)
    _, r3 = await _create_and_activate(client, token)
    assert r1.status_code == 200 and r2.status_code == 200
    assert r3.status_code == 409
    assert r3.json()["error"]["details"]["reason"] == "free_active_limit"

    # Завершить и удалить первый — место освобождается.
    await client.post(f"/api/v1/events/{first}/complete", headers=auth_headers(token))
    deleted = await client.delete(f"/api/v1/events/{first}", headers=auth_headers(token))
    assert deleted.status_code in (200, 204)
    _, r4 = await _create_and_activate(client, token)
    assert r4.status_code == 200


@pytest.mark.asyncio
async def test_free_monthly_limit_counts_deleted(client: AsyncClient, monkeypatch) -> None:
    monkeypatch.setattr(settings, "FREE_ACTIVE_EVENTS", 1)
    monkeypatch.setattr(settings, "FREE_EVENTS_PER_MONTH", 2)
    token = await authenticate(client)
    for _ in range(2):
        event_id, resp = await _create_and_activate(client, token)
        assert resp.status_code == 200
        await client.post(f"/api/v1/events/{event_id}/complete", headers=auth_headers(token))
        await client.delete(f"/api/v1/events/{event_id}", headers=auth_headers(token))
    _, blocked = await _create_and_activate(client, token)
    assert blocked.status_code == 409
    assert blocked.json()["error"]["details"]["reason"] == "free_events_limit"

    me = await client.get("/api/v1/me/entitlements", headers=auth_headers(token))
    body = me.json()
    assert body["free_events_left"] == 0
    assert body["free_active_left"] == 1


def test_pricing_v2_switch(monkeypatch) -> None:
    monkeypatch.setattr(settings, "PRICING_V2_FROM", "2099-01-01T00:00:00+03:00")
    assert payment_service.extend_price_kopecks("3m", 250) == 49000
    assert payment_service.frames_upgrade_price_per_guest_kopecks() == 500

    monkeypatch.setattr(settings, "PRICING_V2_FROM", "2000-01-01T00:00:00+03:00")
    assert payment_service.extend_price_kopecks("3m", 25) == 49000      # минимум
    assert payment_service.extend_price_kopecks("3m", 100) == 100000    # 10 ₽ × 100
    assert payment_service.extend_price_kopecks("1y", 250) == 800000    # 32 ₽ × 250
    assert payment_service.frames_upgrade_price_per_guest_kopecks() == 1000
    assert event_service.price_for_guests(1000) == (7690 + 750 * 35) * 100
    assert event_service.retention_days(payment_service.Plan.P250) == 180
    assert event_service.retention_days(payment_service.Plan.FREE) == 30


def test_purge_due_respects_not_before(monkeypatch) -> None:
    monkeypatch.setattr(settings, "STORAGE_PURGE_NOT_BEFORE", "2030-01-01T00:00:00+00:00")
    now = datetime.now(timezone.utc)
    expired = Event(status=EventStatus.COMPLETED, expires_at=now - timedelta(days=10))
    assert storage_purge.purge_due_at(expired) == datetime(2030, 1, 1, tzinfo=timezone.utc)

    monkeypatch.setattr(settings, "STORAGE_PURGE_NOT_BEFORE", "2000-01-01T00:00:00+00:00")
    assert storage_purge.purge_due_at(expired) == expired.expires_at
    draft = Event(status=EventStatus.DRAFT, expires_at=now - timedelta(days=10))
    assert storage_purge.purge_due_at(draft) is None
