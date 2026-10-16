from datetime import datetime, timedelta, timezone

import pytest
from httpx import AsyncClient

from app.core.config import settings
from tests.helpers import auth_headers, authenticate, fp, future_event_payload


async def _create_solo(client: AsyncClient, token: str, title: str = "Грузия") -> dict:
    resp = await client.post("/api/v1/events/solo", json={"title": title}, headers=auth_headers(token))
    assert resp.status_code == 201, resp.text
    return resp.json()


async def _owner_session(client: AsyncClient, token: str, short_code: str) -> dict:
    resp = await client.post(
        "/api/v1/guest/sessions",
        json={"short_code": short_code, "name": "Я", "fingerprint": fp("owner")},
        headers=auth_headers(token),
    )
    assert resp.status_code == 201, resp.text
    return resp.json()


@pytest.mark.asyncio
async def test_create_solo_is_active_with_30_day_retention(client: AsyncClient) -> None:
    token = await authenticate(client)
    ev = await _create_solo(client, token)
    assert ev["kind"] == "solo"
    assert ev["status"] == "active"
    assert ev["settings"]["max_guests"] == 1
    expires = datetime.fromisoformat(ev["expires_at"])
    delta = expires - datetime.now(timezone.utc)
    assert timedelta(days=29) < delta <= timedelta(days=30, minutes=1)

    listed = await client.get("/api/v1/events/", headers=auth_headers(token))
    assert [e["kind"] for e in listed.json()] == ["solo"]


@pytest.mark.asyncio
async def test_solo_is_visible_only_to_owner(client: AsyncClient) -> None:
    token = await authenticate(client)
    ev = await _create_solo(client, token)

    stranger = await client.post(
        "/api/v1/guest/sessions",
        json={"short_code": ev["short_code"], "name": "Чужой", "fingerprint": fp("x")},
    )
    assert stranger.status_code == 404
    preview = await client.get(f"/api/v1/guest/events/{ev['short_code']}")
    assert preview.status_code == 404

    owner = await _owner_session(client, token, ev["short_code"])
    assert owner["frames_remaining"] == settings.SOLO_FREE_FRAMES_PER_MONTH


@pytest.mark.asyncio
async def test_solo_monthly_quota_blocks_presign(client: AsyncClient, monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(settings, "SOLO_FREE_FRAMES_PER_MONTH", 2)
    token = await authenticate(client)
    ev = await _create_solo(client, token)
    session = await _owner_session(client, token, ev["short_code"])
    assert session["frames_remaining"] == 2
    headers = {"X-Guest-Token": session["guest_token"]}
    body = {"content_type": "image/jpeg", "size_bytes": 1_000_000}

    for _ in range(2):
        ok = await client.post("/api/v1/guest/frames/presign", json=body, headers=headers)
        assert ok.status_code == 200, ok.text
    blocked = await client.post("/api/v1/guest/frames/presign", json=body, headers=headers)
    assert blocked.status_code == 409
    assert "solo_month_limit" in blocked.text


@pytest.mark.asyncio
async def test_solo_quota_is_shared_between_albums(client: AsyncClient, monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(settings, "SOLO_FREE_FRAMES_PER_MONTH", 2)
    token = await authenticate(client)
    first = await _create_solo(client, token, "Первый")
    second = await _create_solo(client, token, "Второй")
    s1 = await _owner_session(client, token, first["short_code"])
    s2 = await _owner_session(client, token, second["short_code"])
    body = {"content_type": "image/jpeg", "size_bytes": 1_000_000}
    for _ in range(2):
        r = await client.post("/api/v1/guest/frames/presign", json=body, headers={"X-Guest-Token": s1["guest_token"]})
        assert r.status_code == 200, r.text
    blocked = await client.post("/api/v1/guest/frames/presign", json=body, headers={"X-Guest-Token": s2["guest_token"]})
    assert blocked.status_code == 409


@pytest.mark.asyncio
async def test_solo_does_not_use_free_event_limits(client: AsyncClient, monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(settings, "PRICING_V2_FROM", "2020-01-01T00:00:00+00:00")
    monkeypatch.setattr(settings, "FREE_ACTIVE_EVENTS", 2)
    monkeypatch.setattr(settings, "FREE_EVENTS_PER_MONTH", 2)
    token = await authenticate(client)
    for i in range(4):
        await _create_solo(client, token, f"Соло {i}")
    for i in range(2):
        created = await client.post("/api/v1/events/", json=future_event_payload(f"E{i}"), headers=auth_headers(token))
        ok = await client.post(f"/api/v1/events/{created.json()['id']}/activate", headers=auth_headers(token))
        assert ok.status_code == 200, ok.text


@pytest.mark.asyncio
async def test_solo_cannot_be_upgraded(client: AsyncClient) -> None:
    token = await authenticate(client)
    ev = await _create_solo(client, token)
    resp = await client.post(
        f"/api/v1/events/{ev['id']}/upgrade", json={"kind": "frames"},
        headers={**auth_headers(token), "Idempotency-Key": "solo-upgrade-test-1"},
    )
    assert resp.status_code == 409


@pytest.mark.asyncio
async def test_entitlements_and_pricing_expose_solo_and_plus(client: AsyncClient) -> None:
    token = await authenticate(client)
    ent = (await client.get("/api/v1/me/entitlements", headers=auth_headers(token))).json()
    assert ent["plus"] is False
    assert ent["solo_frames_per_month"] == settings.SOLO_FREE_FRAMES_PER_MONTH
    assert ent["solo_frames_left"] == settings.SOLO_FREE_FRAMES_PER_MONTH
    assert ent["features"]["solo_album"] is True
    assert ent["mini_albums_limit"] == settings.MINI_FREE_ALBUMS

    pricing = (await client.get("/api/v1/pricing")).json()
    assert [o["period"] for o in pricing["solo_extend"]] == ["3m", "6m", "1y"]
    assert pricing["solo_extend"][0]["price_kopecks"] == 9900
    assert pricing["plus"]["month_kopecks"] == 22900
    assert pricing["plus"]["year_kopecks"] == 219000
    assert pricing["plus"]["enabled"] is False


@pytest.mark.asyncio
async def test_deleting_solo_frees_storage_quota(client: AsyncClient, monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(settings, "SOLO_FREE_STORED_FRAMES", 1)
    token = await authenticate(client)
    ev = await _create_solo(client, token)
    session = await _owner_session(client, token, ev["short_code"])
    headers = {"X-Guest-Token": session["guest_token"]}
    body = {"content_type": "image/jpeg", "size_bytes": 1_000_000}
    assert (await client.post("/api/v1/guest/frames/presign", json=body, headers=headers)).status_code == 200
    assert (await client.post("/api/v1/guest/frames/presign", json=body, headers=headers)).status_code == 409

    deleted = await client.delete(f"/api/v1/events/{ev['id']}", headers=auth_headers(token))
    assert deleted.status_code == 204
    ent = (await client.get("/api/v1/me/entitlements", headers=auth_headers(token))).json()
    assert ent["solo_stored_used"] == 0
