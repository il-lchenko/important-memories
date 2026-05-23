from datetime import datetime, timedelta, timezone
from uuid import UUID

import pytest
from httpx import AsyncClient
from sqlalchemy import select

from app.core.db import SessionLocal
from app.domain.models import Event, EventSettings, Frame, FrameStatus, RevealMode
from tests.helpers import auth_headers, authenticate, future_event_payload


async def _seed_uploaded_frame(
    frame_id: UUID,
    *,
    captured_at: datetime,
    s3_key: str = "events/test/frames/test.jpg",
    thumbnail_url: str | None = None,
) -> None:
    async with SessionLocal() as s:
        frame = (await s.execute(select(Frame).where(Frame.id == frame_id))).scalar_one()
        frame.status = FrameStatus.UPLOADED
        frame.captured_at = captured_at
        frame.thumbnail_url = thumbnail_url or f"events/test/thumbs/{frame_id}.jpg"
        await s.commit()


async def _set_reveal_mode(event_id: UUID, mode: RevealMode, reveal_at: datetime | None = None) -> None:
    async with SessionLocal() as s:
        settings = (
            await s.execute(select(EventSettings).where(EventSettings.event_id == event_id))
        ).scalar_one()
        settings.reveal_mode = mode
        settings.reveal_at = reveal_at
        await s.commit()


async def _activate(client: AsyncClient, token: str) -> dict:
    create = await client.post(
        "/api/v1/events/", json=future_event_payload(), headers=auth_headers(token)
    )
    event = create.json()
    await client.post(f"/api/v1/events/{event['id']}/activate", headers=auth_headers(token))
    return event


async def _join_and_register(client: AsyncClient, event: dict, fp: str = "fp-1") -> tuple[str, UUID]:
    join = await client.post(
        "/api/v1/guest/sessions",
        json={"short_code": event["short_code"], "name": "Аня", "fingerprint": fp},
    )
    guest_token = join.json()["guest_token"]
    headers = {"X-Guest-Token": guest_token}
    presign = await client.post(
        "/api/v1/guest/frames/presign",
        json={"content_type": "image/jpeg", "size_bytes": 1000},
        headers=headers,
    )
    frame_id = UUID(presign.json()["frame_id"])
    await client.post(
        "/api/v1/guest/frames/",
        json={
            "frame_id": str(frame_id),
            "captured_at": datetime.now(timezone.utc).isoformat(),
            "width": 1080,
            "height": 1080,
        },
        headers=headers,
    )
    return guest_token, frame_id


@pytest.mark.asyncio
async def test_album_instant_shows_uploaded_frames(client: AsyncClient) -> None:
    token = await authenticate(client)
    event = await _activate(client, token)
    _, frame_id = await _join_and_register(client, event)
    await _seed_uploaded_frame(frame_id, captured_at=datetime.now(timezone.utc))

    resp = await client.get(
        f"/api/v1/events/{event['id']}/album", headers=auth_headers(token)
    )
    assert resp.status_code == 200, resp.text
    data = resp.json()
    assert data["revealed"] is True
    assert data["total_frames"] == 1
    assert len(data["items"]) == 1
    assert data["items"][0]["guest_name"] == "Аня"
    assert data["items"][0]["thumbnail_url"]
    assert data["items"][0]["full_url"]


@pytest.mark.asyncio
async def test_album_delayed_returns_empty_until_revealed(client: AsyncClient) -> None:
    token = await authenticate(client)
    event = await _activate(client, token)
    _, frame_id = await _join_and_register(client, event)
    await _seed_uploaded_frame(frame_id, captured_at=datetime.now(timezone.utc))

    await _set_reveal_mode(
        UUID(event["id"]),
        RevealMode.DELAYED,
        reveal_at=datetime.now(timezone.utc) + timedelta(days=1),
    )

    resp = await client.get(
        f"/api/v1/events/{event['id']}/album", headers=auth_headers(token)
    )
    data = resp.json()
    assert data["revealed"] is False
    assert data["items"] == []
    assert data["total_frames"] == 1

    reveal = await client.post(
        f"/api/v1/events/{event['id']}/reveal", headers=auth_headers(token)
    )
    assert reveal.status_code == 200
    assert reveal.json()["status"] == "completed"

    resp = await client.get(
        f"/api/v1/events/{event['id']}/album", headers=auth_headers(token)
    )
    data = resp.json()
    assert data["revealed"] is True
    assert len(data["items"]) == 1


@pytest.mark.asyncio
async def test_album_pagination_via_cursor(client: AsyncClient) -> None:
    token = await authenticate(client)
    event = await _activate(client, token)
    now = datetime.now(timezone.utc)
    for i in range(3):
        _, fid = await _join_and_register(client, event, fp=f"fp-{i}")
        await _seed_uploaded_frame(fid, captured_at=now + timedelta(seconds=i))

    first = await client.get(
        f"/api/v1/events/{event['id']}/album?limit=2", headers=auth_headers(token)
    )
    data = first.json()
    assert len(data["items"]) == 2
    assert data["next_cursor"]

    second = await client.get(
        f"/api/v1/events/{event['id']}/album?limit=2&cursor={data['next_cursor']}",
        headers=auth_headers(token),
    )
    rest = second.json()
    assert len(rest["items"]) == 1
    assert rest["next_cursor"] is None


@pytest.mark.asyncio
async def test_album_forbidden_for_other_user(client: AsyncClient) -> None:
    owner = await authenticate(client, "owner@example.com")
    stranger = await authenticate(client, "stranger@example.com")
    event = await _activate(client, owner)
    resp = await client.get(
        f"/api/v1/events/{event['id']}/album", headers=auth_headers(stranger)
    )
    assert resp.status_code == 403


@pytest.mark.asyncio
async def test_album_guest_sees_event(client: AsyncClient) -> None:
    token = await authenticate(client)
    event = await _activate(client, token)
    guest_token, frame_id = await _join_and_register(client, event)
    await _seed_uploaded_frame(frame_id, captured_at=datetime.now(timezone.utc))

    resp = await client.get(
        f"/api/v1/events/{event['id']}/album",
        headers={"X-Guest-Token": guest_token},
    )
    assert resp.status_code == 200
    items = resp.json()["items"]
    assert len(items) == 1
    assert items[0]["is_mine"] is True


@pytest.mark.asyncio
async def test_album_guest_from_other_event_forbidden(client: AsyncClient) -> None:
    token = await authenticate(client)
    event_a = await _activate(client, token)
    event_b = await _activate(client, token)
    guest_a_token, _ = await _join_and_register(client, event_a)
    resp = await client.get(
        f"/api/v1/events/{event_b['id']}/album",
        headers={"X-Guest-Token": guest_a_token},
    )
    assert resp.status_code == 403
