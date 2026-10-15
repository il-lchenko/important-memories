import pytest
from httpx import AsyncClient

from app.core.config import settings
from tests.helpers import auth_headers, authenticate, future_event_payload


async def _create_and_activate(client: AsyncClient, token: str):
    created = await client.post(
        "/api/v1/events/", json=future_event_payload(), headers=auth_headers(token)
    )
    assert created.status_code == 201, created.text
    return await client.post(
        f"/api/v1/events/{created.json()['id']}/activate", headers=auth_headers(token)
    )


@pytest.mark.asyncio
async def test_entitlements_default_unlimited(client: AsyncClient) -> None:
    token = await authenticate(client)
    resp = await client.get("/api/v1/me/entitlements", headers=auth_headers(token))
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["tier"] == "free"
    assert body["is_admin"] is False
    assert body["subscription_enabled"] is False
    assert body["free_events_per_month"] is None
    assert body["free_events_left"] is None
    assert body["features"] == {"solo_album": False, "mini_albums": False}


@pytest.mark.asyncio
async def test_entitlements_requires_auth(client: AsyncClient) -> None:
    resp = await client.get("/api/v1/me/entitlements")
    assert resp.status_code == 401


@pytest.mark.asyncio
async def test_free_events_limit_blocks_activation(
    client: AsyncClient, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.setattr(settings, "FREE_EVENTS_PER_MONTH", 1)
    token = await authenticate(client)

    first = await _create_and_activate(client, token)
    assert first.status_code == 200, first.text

    ent = await client.get("/api/v1/me/entitlements", headers=auth_headers(token))
    assert ent.json()["free_events_used"] == 1
    assert ent.json()["free_events_left"] == 0

    second = await _create_and_activate(client, token)
    assert second.status_code == 409
