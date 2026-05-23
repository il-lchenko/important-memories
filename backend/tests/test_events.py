from datetime import datetime, timedelta, timezone

import pytest
from httpx import AsyncClient

from tests.helpers import auth_headers, authenticate, future_event_payload


@pytest.mark.asyncio
async def test_create_event_returns_draft_with_settings(client: AsyncClient) -> None:
    token = await authenticate(client)
    response = await client.post(
        "/api/v1/events/", json=future_event_payload(), headers=auth_headers(token)
    )
    assert response.status_code == 201, response.text
    data = response.json()
    assert data["status"] == "draft"
    assert len(data["short_code"]) == 8
    assert data["settings"]["plan"] == "free"
    assert data["settings"]["max_guests"] == 5
    assert data["settings"]["frames_per_guest"] == 24


@pytest.mark.asyncio
async def test_create_event_rejects_end_before_start(client: AsyncClient) -> None:
    token = await authenticate(client)
    payload = future_event_payload()
    payload["end_at"] = payload["start_at"]
    response = await client.post(
        "/api/v1/events/", json=payload, headers=auth_headers(token)
    )
    assert response.status_code == 422


@pytest.mark.asyncio
async def test_create_event_requires_auth(client: AsyncClient) -> None:
    response = await client.post("/api/v1/events/", json=future_event_payload())
    assert response.status_code == 401


@pytest.mark.asyncio
async def test_list_events_only_returns_own(client: AsyncClient) -> None:
    t1 = await authenticate(client, "a@example.com")
    t2 = await authenticate(client, "b@example.com")

    await client.post("/api/v1/events/", json=future_event_payload("A"), headers=auth_headers(t1))
    await client.post("/api/v1/events/", json=future_event_payload("B"), headers=auth_headers(t2))

    resp = await client.get("/api/v1/events/", headers=auth_headers(t1))
    assert resp.status_code == 200
    items = resp.json()
    assert len(items) == 1
    assert items[0]["title"] == "A"


@pytest.mark.asyncio
async def test_get_event_forbidden_for_other_user(client: AsyncClient) -> None:
    t1 = await authenticate(client, "owner@example.com")
    t2 = await authenticate(client, "stranger@example.com")
    create = await client.post(
        "/api/v1/events/", json=future_event_payload(), headers=auth_headers(t1)
    )
    event_id = create.json()["id"]
    resp = await client.get(f"/api/v1/events/{event_id}", headers=auth_headers(t2))
    assert resp.status_code == 403


@pytest.mark.asyncio
async def test_update_settings_changes_plan_and_limits(client: AsyncClient) -> None:
    token = await authenticate(client)
    create = await client.post(
        "/api/v1/events/", json=future_event_payload(), headers=auth_headers(token)
    )
    event_id = create.json()["id"]
    resp = await client.patch(
        f"/api/v1/events/{event_id}/settings",
        json={"plan": "p50", "frames_per_guest": 36, "lut_preset": "fuji"},
        headers=auth_headers(token),
    )
    assert resp.status_code == 200, resp.text
    settings = resp.json()["settings"]
    assert settings["plan"] == "p50"
    assert settings["max_guests"] == 50
    assert settings["frames_per_guest"] == 36
    assert settings["lut_preset"] == "fuji"


@pytest.mark.asyncio
async def test_delayed_reveal_requires_reveal_at_after_end(client: AsyncClient) -> None:
    token = await authenticate(client)
    create = await client.post(
        "/api/v1/events/", json=future_event_payload(), headers=auth_headers(token)
    )
    event_id = create.json()["id"]
    end_at = datetime.fromisoformat(create.json()["end_at"])

    bad = await client.patch(
        f"/api/v1/events/{event_id}/settings",
        json={
            "reveal_mode": "delayed",
            "reveal_at": (end_at - timedelta(hours=1)).isoformat(),
        },
        headers=auth_headers(token),
    )
    assert bad.status_code == 409

    good = await client.patch(
        f"/api/v1/events/{event_id}/settings",
        json={
            "reveal_mode": "delayed",
            "reveal_at": (end_at + timedelta(hours=2)).isoformat(),
        },
        headers=auth_headers(token),
    )
    assert good.status_code == 200, good.text


@pytest.mark.asyncio
async def test_activate_and_complete_flow(client: AsyncClient) -> None:
    token = await authenticate(client)
    create = await client.post(
        "/api/v1/events/", json=future_event_payload(), headers=auth_headers(token)
    )
    event_id = create.json()["id"]

    activate = await client.post(
        f"/api/v1/events/{event_id}/activate", headers=auth_headers(token)
    )
    assert activate.status_code == 200
    assert activate.json()["status"] == "active"

    complete = await client.post(
        f"/api/v1/events/{event_id}/complete", headers=auth_headers(token)
    )
    assert complete.status_code == 200
    assert complete.json()["status"] == "completed"


@pytest.mark.asyncio
async def test_qr_endpoint_returns_png(client: AsyncClient) -> None:
    token = await authenticate(client)
    create = await client.post(
        "/api/v1/events/", json=future_event_payload(), headers=auth_headers(token)
    )
    event_id = create.json()["id"]
    resp = await client.get(f"/api/v1/events/{event_id}/qr", headers=auth_headers(token))
    assert resp.status_code == 200
    assert resp.headers["content-type"] == "image/png"
    assert resp.content[:8] == b"\x89PNG\r\n\x1a\n"
