from datetime import datetime, timezone

import pytest
from httpx import AsyncClient

from tests.helpers import auth_headers, authenticate, future_event_payload


async def _setup_active_guest(client: AsyncClient, frames_per_guest: int | None = None) -> str:
    token = await authenticate(client)
    create = await client.post(
        "/api/v1/events/", json=future_event_payload(), headers=auth_headers(token)
    )
    event = create.json()
    if frames_per_guest is not None:
        await client.patch(
            f"/api/v1/events/{event['id']}/settings",
            json={"frames_per_guest": frames_per_guest},
            headers=auth_headers(token),
        )
    await client.post(
        f"/api/v1/events/{event['id']}/activate", headers=auth_headers(token)
    )
    detail = await client.get(f"/api/v1/events/{event['id']}", headers=auth_headers(token))
    join = await client.post(
        "/api/v1/guest/sessions",
        json={"short_code": detail.json()["short_code"], "name": "G", "fingerprint": "fp-1"},
    )
    return join.json()["guest_token"]


@pytest.mark.asyncio
async def test_presign_returns_upload_url_and_creates_pending_frame(client: AsyncClient) -> None:
    token = await _setup_active_guest(client)
    resp = await client.post(
        "/api/v1/guest/frames/presign",
        json={"content_type": "image/jpeg", "size_bytes": 1_000_000},
        headers={"X-Guest-Token": token},
    )
    assert resp.status_code == 200, resp.text
    data = resp.json()
    assert data["upload_url"].startswith("http")
    assert data["frame_id"]


@pytest.mark.asyncio
async def test_presign_rejects_invalid_content_type(client: AsyncClient) -> None:
    token = await _setup_active_guest(client)
    resp = await client.post(
        "/api/v1/guest/frames/presign",
        json={"content_type": "application/pdf", "size_bytes": 1000},
        headers={"X-Guest-Token": token},
    )
    assert resp.status_code == 422


@pytest.mark.asyncio
async def test_presign_requires_guest_token(client: AsyncClient) -> None:
    resp = await client.post(
        "/api/v1/guest/frames/presign",
        json={"content_type": "image/jpeg", "size_bytes": 1000},
    )
    assert resp.status_code == 401


@pytest.mark.asyncio
async def test_quota_enforced(client: AsyncClient) -> None:
    token = await _setup_active_guest(client, frames_per_guest=2)
    for _ in range(2):
        r = await client.post(
            "/api/v1/guest/frames/presign",
            json={"content_type": "image/jpeg", "size_bytes": 1000},
            headers={"X-Guest-Token": token},
        )
        assert r.status_code == 200, r.text
    third = await client.post(
        "/api/v1/guest/frames/presign",
        json={"content_type": "image/jpeg", "size_bytes": 1000},
        headers={"X-Guest-Token": token},
    )
    assert third.status_code == 409


@pytest.mark.asyncio
async def test_register_frame_marks_uploaded_and_decrements_remaining(client: AsyncClient) -> None:
    token = await _setup_active_guest(client, frames_per_guest=3)
    presign = await client.post(
        "/api/v1/guest/frames/presign",
        json={"content_type": "image/jpeg", "size_bytes": 1000},
        headers={"X-Guest-Token": token},
    )
    frame_id = presign.json()["frame_id"]

    resp = await client.post(
        "/api/v1/guest/frames/",
        json={
            "frame_id": frame_id,
            "captured_at": datetime.now(timezone.utc).isoformat(),
            "width": 1080,
            "height": 1080,
        },
        headers={"X-Guest-Token": token},
    )
    assert resp.status_code == 201, resp.text
    body = resp.json()
    assert body["status"] == "uploaded"
    assert body["frames_remaining"] == 2


@pytest.mark.asyncio
async def test_register_other_guests_frame_forbidden(client: AsyncClient) -> None:
    token1 = await _setup_active_guest(client)
    presign = await client.post(
        "/api/v1/guest/frames/presign",
        json={"content_type": "image/jpeg", "size_bytes": 1000},
        headers={"X-Guest-Token": token1},
    )
    frame_id = presign.json()["frame_id"]

    # Создаём второго гостя на новом эвенте (отдельная сетка)
    token2 = await _setup_active_guest(client)
    resp = await client.post(
        "/api/v1/guest/frames/",
        json={
            "frame_id": frame_id,
            "captured_at": datetime.now(timezone.utc).isoformat(),
            "width": 100,
            "height": 100,
        },
        headers={"X-Guest-Token": token2},
    )
    assert resp.status_code == 403
