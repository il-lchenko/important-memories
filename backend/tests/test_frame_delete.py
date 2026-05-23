from datetime import datetime, timezone
from uuid import UUID

import pytest
from httpx import AsyncClient
from sqlalchemy import select

from app.core.db import SessionLocal
from app.domain.models import Frame, FrameStatus
from tests.helpers import auth_headers, authenticate, future_event_payload


async def _setup(client: AsyncClient, fp: str = "fp-1") -> tuple[str, dict, str, UUID]:
    token = await authenticate(client)
    create = await client.post(
        "/api/v1/events/", json=future_event_payload(), headers=auth_headers(token)
    )
    event = create.json()
    await client.post(f"/api/v1/events/{event['id']}/activate", headers=auth_headers(token))
    join = await client.post(
        "/api/v1/guest/sessions",
        json={"short_code": event["short_code"], "name": "G", "fingerprint": fp},
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


async def _frame_status(frame_id: UUID) -> FrameStatus:
    async with SessionLocal() as s:
        frame = (await s.execute(select(Frame).where(Frame.id == frame_id))).scalar_one()
        return frame.status


@pytest.mark.asyncio
async def test_host_can_delete_any_frame(client: AsyncClient) -> None:
    token, event, _, frame_id = await _setup(client)
    resp = await client.delete(
        f"/api/v1/events/{event['id']}/frames/{frame_id}",
        headers=auth_headers(token),
    )
    assert resp.status_code == 204
    assert (await _frame_status(frame_id)) == FrameStatus.DELETED


@pytest.mark.asyncio
async def test_owner_guest_can_delete_own_frame(client: AsyncClient) -> None:
    _, event, guest_token, frame_id = await _setup(client)
    resp = await client.delete(
        f"/api/v1/events/{event['id']}/frames/{frame_id}",
        headers={"X-Guest-Token": guest_token},
    )
    assert resp.status_code == 204
    assert (await _frame_status(frame_id)) == FrameStatus.DELETED


@pytest.mark.asyncio
async def test_other_guest_cannot_delete_frame(client: AsyncClient) -> None:
    token, event, _, frame_id = await _setup(client)
    other_join = await client.post(
        "/api/v1/guest/sessions",
        json={"short_code": event["short_code"], "name": "Other", "fingerprint": "fp-2"},
    )
    other_token = other_join.json()["guest_token"]
    resp = await client.delete(
        f"/api/v1/events/{event['id']}/frames/{frame_id}",
        headers={"X-Guest-Token": other_token},
    )
    assert resp.status_code == 403


@pytest.mark.asyncio
async def test_delete_requires_auth(client: AsyncClient) -> None:
    _, event, _, frame_id = await _setup(client)
    resp = await client.delete(f"/api/v1/events/{event['id']}/frames/{frame_id}")
    assert resp.status_code == 401
