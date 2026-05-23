import pytest
from httpx import AsyncClient

from tests.helpers import auth_headers, authenticate, future_event_payload


async def _make_active_event(client: AsyncClient, token: str, plan: str = "free") -> dict:
    create = await client.post(
        "/api/v1/events/", json=future_event_payload(), headers=auth_headers(token)
    )
    event = create.json()
    if plan != "free":
        await client.patch(
            f"/api/v1/events/{event['id']}/settings",
            json={"plan": plan},
            headers=auth_headers(token),
        )
    await client.post(
        f"/api/v1/events/{event['id']}/activate", headers=auth_headers(token)
    )
    detail = await client.get(f"/api/v1/events/{event['id']}", headers=auth_headers(token))
    return detail.json()


@pytest.mark.asyncio
async def test_guest_join_creates_session(client: AsyncClient) -> None:
    token = await authenticate(client)
    event = await _make_active_event(client, token)

    resp = await client.post(
        "/api/v1/guest/sessions",
        json={"short_code": event["short_code"], "name": "Аня", "fingerprint": "fp-1"},
    )
    assert resp.status_code == 201, resp.text
    data = resp.json()
    assert data["guest_token"]
    assert data["frames_used"] == 0
    assert data["frames_remaining"] == 24
    assert data["event"]["id"] == event["id"]


@pytest.mark.asyncio
async def test_guest_join_same_fingerprint_returns_existing(client: AsyncClient) -> None:
    token = await authenticate(client)
    event = await _make_active_event(client, token)
    payload = {"short_code": event["short_code"], "name": "Аня", "fingerprint": "fp-1"}

    first = await client.post("/api/v1/guest/sessions", json=payload)
    second = await client.post("/api/v1/guest/sessions", json=payload)
    assert first.status_code == 201
    assert second.status_code == 201
    assert first.json()["guest_id"] == second.json()["guest_id"]


@pytest.mark.asyncio
async def test_guest_join_returns_404_for_unknown_event(client: AsyncClient) -> None:
    resp = await client.post(
        "/api/v1/guest/sessions",
        json={"short_code": "missing1", "name": "X", "fingerprint": "fp-1"},
    )
    assert resp.status_code == 404


@pytest.mark.asyncio
async def test_guest_join_rejected_for_draft_event(client: AsyncClient) -> None:
    token = await authenticate(client)
    create = await client.post(
        "/api/v1/events/", json=future_event_payload(), headers=auth_headers(token)
    )
    short_code = create.json()["short_code"]
    resp = await client.post(
        "/api/v1/guest/sessions",
        json={"short_code": short_code, "name": "X", "fingerprint": "fp-1"},
    )
    assert resp.status_code == 409


@pytest.mark.asyncio
async def test_guest_limit_enforced(client: AsyncClient) -> None:
    token = await authenticate(client)
    event = await _make_active_event(client, token)
    short_code = event["short_code"]

    for i in range(5):
        r = await client.post(
            "/api/v1/guest/sessions",
            json={"short_code": short_code, "name": f"G{i}", "fingerprint": f"fp-{i}"},
        )
        assert r.status_code == 201, r.text

    over = await client.post(
        "/api/v1/guest/sessions",
        json={"short_code": short_code, "name": "Over", "fingerprint": "fp-over"},
    )
    assert over.status_code == 409


@pytest.mark.asyncio
async def test_settings_locked_after_first_guest(client: AsyncClient) -> None:
    token = await authenticate(client)
    event = await _make_active_event(client, token)
    await client.post(
        "/api/v1/guest/sessions",
        json={"short_code": event["short_code"], "name": "X", "fingerprint": "fp-1"},
    )
    resp = await client.patch(
        f"/api/v1/events/{event['id']}/settings",
        json={"frames_per_guest": 50},
        headers=auth_headers(token),
    )
    assert resp.status_code == 409
