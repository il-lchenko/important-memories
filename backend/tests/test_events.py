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
        json={"plan": "p50", "frames_per_guest": 24, "lut_preset": "fuji400h"},
        headers=auth_headers(token),
    )
    assert resp.status_code == 200, resp.text
    settings = resp.json()["settings"]
    assert settings["plan"] == "p50"
    assert settings["max_guests"] == 50
    assert settings["frames_per_guest"] == 24
    assert settings["lut_preset"] == "fuji400h"


@pytest.mark.asyncio
async def test_delayed_reveal_rejects_past_reveal_at(client: AsyncClient) -> None:
    """Delayed-режим требует reveal_at строго в будущем.
    Валидация "reveal_at после end_at" была убрана — reveal может быть
    когда угодно после установки, включая до окончания События."""
    token = await authenticate(client)
    create = await client.post(
        "/api/v1/events/", json=future_event_payload(), headers=auth_headers(token)
    )
    event_id = create.json()["id"]
    now = datetime.now(timezone.utc)

    bad = await client.patch(
        f"/api/v1/events/{event_id}/settings",
        json={
            "reveal_mode": "delayed",
            "reveal_at": (now - timedelta(hours=1)).isoformat(),
        },
        headers=auth_headers(token),
    )
    assert bad.status_code == 409

    good = await client.patch(
        f"/api/v1/events/{event_id}/settings",
        json={
            "reveal_mode": "delayed",
            "reveal_at": (now + timedelta(hours=2)).isoformat(),
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


@pytest.mark.asyncio
async def test_frames_over_base_require_payment(client: AsyncClient) -> None:
    token = await authenticate(client)
    payload = future_event_payload()
    payload["frames_per_guest"] = 60
    blocked = await client.post("/api/v1/events/", json=payload, headers=auth_headers(token))
    assert blocked.status_code == 409, blocked.text
    assert "frames_over_base" in blocked.text

    payload["frames_per_guest"] = 30
    ok = await client.post("/api/v1/events/", json=payload, headers=auth_headers(token))
    assert ok.status_code == 201, ok.text
    event_id = ok.json()["id"]
    over = await client.patch(f"/api/v1/events/{event_id}/settings", json={"frames_per_guest": 45}, headers=auth_headers(token))
    assert over.status_code == 409
    same = await client.patch(f"/api/v1/events/{event_id}/settings", json={"frames_per_guest": 24}, headers=auth_headers(token))
    assert same.status_code == 200, same.text


@pytest.mark.asyncio
async def test_host_sees_guests_with_frame_counts(client: AsyncClient) -> None:
    token = await authenticate(client)
    created = await client.post("/api/v1/events/", json=future_event_payload("G"), headers=auth_headers(token))
    event = created.json()
    await client.post(f"/api/v1/events/{event['id']}/activate", headers=auth_headers(token))
    code = (await client.get(f"/api/v1/events/{event['id']}", headers=auth_headers(token))).json()["short_code"]
    join = await client.post(
        "/api/v1/guest/sessions", json={"short_code": code, "name": "Аня", "fingerprint": "a1b2c3d4"}
    )
    assert join.status_code == 201, join.text
    guests = await client.get(f"/api/v1/events/{event['id']}/guests", headers=auth_headers(token))
    assert guests.status_code == 200, guests.text
    body = guests.json()
    assert len(body) == 1 and body[0]["name"] == "Аня" and body[0]["frames_count"] == 0
    stranger = await authenticate(client, "other@example.com")
    forbidden = await client.get(f"/api/v1/events/{event['id']}/guests", headers=auth_headers(stranger))
    assert forbidden.status_code == 403


@pytest.mark.asyncio
async def test_owner_own_session_does_not_lock_settings_but_guest_does(client: AsyncClient) -> None:
    token = await authenticate(client)
    created = await client.post("/api/v1/events/", json=future_event_payload("L"), headers=auth_headers(token))
    event = created.json()
    await client.post(f"/api/v1/events/{event['id']}/activate", headers=auth_headers(token))
    code = (await client.get(f"/api/v1/events/{event['id']}", headers=auth_headers(token))).json()["short_code"]

    owner = await client.post(
        "/api/v1/guest/sessions", json={"short_code": code, "name": "Я", "fingerprint": "0a0a0a0a"},
        headers=auth_headers(token),
    )
    assert owner.status_code == 201, owner.text
    detail = (await client.get(f"/api/v1/events/{event['id']}", headers=auth_headers(token))).json()
    assert detail["settings_locked"] is False
    ok = await client.patch(f"/api/v1/events/{event['id']}/settings", json={"lut_preset": "fuji400h"}, headers=auth_headers(token))
    assert ok.status_code == 200, ok.text

    guest = await client.post("/api/v1/guest/sessions", json={"short_code": code, "name": "Аня", "fingerprint": "1b1b1b1b"})
    assert guest.status_code == 201, guest.text
    detail2 = (await client.get(f"/api/v1/events/{event['id']}", headers=auth_headers(token))).json()
    assert detail2["settings_locked"] is True
    blocked = await client.patch(f"/api/v1/events/{event['id']}/settings", json={"lut_preset": "ilford"}, headers=auth_headers(token))
    assert blocked.status_code == 409
