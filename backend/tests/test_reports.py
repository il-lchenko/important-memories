from datetime import datetime, timezone
from uuid import UUID, uuid4

import pytest
from httpx import AsyncClient

from tests.helpers import auth_headers, authenticate, future_event_payload


async def _make_event_with_frame(client: AsyncClient) -> tuple[str, dict, str, UUID]:
    token = await authenticate(client)
    create = await client.post(
        "/api/v1/events/", json=future_event_payload(), headers=auth_headers(token)
    )
    event = create.json()
    await client.post(f"/api/v1/events/{event['id']}/activate", headers=auth_headers(token))
    join = await client.post(
        "/api/v1/guest/sessions",
        json={"short_code": event["short_code"], "name": "G", "fingerprint": "fp-r"},
    )
    guest_token = join.json()["guest_token"]
    gh = {"X-Guest-Token": guest_token}
    presign = await client.post(
        "/api/v1/guest/frames/presign",
        json={"content_type": "image/jpeg", "size_bytes": 1000},
        headers=gh,
    )
    frame_id = UUID(presign.json()["frame_id"])
    await client.post(
        "/api/v1/guest/frames/",
        json={
            "frame_id": str(frame_id),
            "captured_at": datetime.now(timezone.utc).isoformat(),
            "width": 100,
            "height": 100,
        },
        headers=gh,
    )
    return token, event, guest_token, frame_id


@pytest.mark.asyncio
async def test_guest_can_report_frame(client: AsyncClient) -> None:
    _, _, guest_token, frame_id = await _make_event_with_frame(client)
    resp = await client.post(
        "/api/v1/reports/",
        json={"frame_id": str(frame_id), "category": "nudity"},
        headers={"X-Guest-Token": guest_token},
    )
    assert resp.status_code == 201, resp.text
    body = resp.json()
    assert body["status"] == "open"


@pytest.mark.asyncio
async def test_host_can_report_event(client: AsyncClient) -> None:
    token, event, _, _ = await _make_event_with_frame(client)
    resp = await client.post(
        "/api/v1/reports/",
        json={"event_id": event["id"], "category": "spam", "note": "test"},
        headers=auth_headers(token),
    )
    assert resp.status_code == 201


@pytest.mark.asyncio
async def test_report_requires_frame_or_event(client: AsyncClient) -> None:
    token = await authenticate(client)
    resp = await client.post(
        "/api/v1/reports/",
        json={"category": "spam"},
        headers=auth_headers(token),
    )
    assert resp.status_code == 422


@pytest.mark.asyncio
async def test_report_404_for_unknown_frame(client: AsyncClient) -> None:
    token = await authenticate(client)
    resp = await client.post(
        "/api/v1/reports/",
        json={"frame_id": str(uuid4()), "category": "spam"},
        headers=auth_headers(token),
    )
    assert resp.status_code == 404


@pytest.mark.asyncio
async def test_report_requires_auth(client: AsyncClient) -> None:
    resp = await client.post(
        "/api/v1/reports/", json={"event_id": str(uuid4()), "category": "spam"}
    )
    assert resp.status_code == 401
