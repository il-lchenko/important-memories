from datetime import datetime, timedelta, timezone
from uuid import UUID, uuid4

import pytest
from httpx import AsyncClient
from sqlalchemy import select

from app.core.db import SessionLocal
from app.domain.models import CollectionItem, Event, Frame, FrameStatus, Guest, User
from app.infra import s3_client
from tests.helpers import auth_headers, authenticate, future_event_payload


@pytest.fixture(autouse=True)
def _fake_presign(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(s3_client, "presign_get", lambda key, expires_in=3600: f"http://s3.test/{key}?sig=1")


async def _solo(client: AsyncClient, token: str) -> str:
    r = await client.post("/api/v1/events/solo", json={"title": "Грузия"}, headers=auth_headers(token))
    assert r.status_code == 201, r.text
    return r.json()["id"]


async def _add_frame(event_id: UUID, guest_id: UUID | None, minutes_ago: int = 0) -> UUID:
    async with SessionLocal() as s:
        f = Frame(
            event_id=event_id, guest_id=guest_id, s3_key=f"events/{event_id}/orig-{uuid4().hex[:6]}.jpg",
            preview_url=f"events/{event_id}/prev-{uuid4().hex[:6]}.jpg", status=FrameStatus.UPLOADED,
            captured_at=datetime.now(timezone.utc) - timedelta(minutes=minutes_ago),
        )
        s.add(f)
        await s.commit()
        return f.id


async def test_solo_album_can_be_shared_before_any_reveal(client: AsyncClient) -> None:
    token = await authenticate(client, "share1@example.com")
    solo_id = await _solo(client, token)
    await _add_frame(UUID(solo_id), None)

    r = await client.post(f"/api/v1/events/{solo_id}/public-share/enable", headers=auth_headers(token))
    assert r.status_code == 200, r.text
    link = r.json()["public_share_token"]

    meta = await client.get(f"/api/v1/public/albums/{link}")
    assert meta.status_code == 200 and meta.json()["title"] == "Грузия" and meta.json()["total_frames"] == 1
    frames = await client.get(f"/api/v1/public/albums/{link}/frames")
    assert frames.status_code == 200 and len(frames.json()["items"]) == 1

    r2 = await client.post(f"/api/v1/events/{solo_id}/public-share/regenerate", headers=auth_headers(token))
    assert r2.json()["public_share_token"] != link
    assert (await client.get(f"/api/v1/public/albums/{link}")).status_code == 404

    new = r2.json()["public_share_token"]
    assert (await client.delete(f"/api/v1/events/{solo_id}/public-share", headers=auth_headers(token))).status_code == 204
    assert (await client.get(f"/api/v1/public/albums/{new}")).status_code == 404


async def test_regular_active_event_still_needs_completion_for_public_link(client: AsyncClient) -> None:
    token = await authenticate(client, "share2@example.com")
    r = await client.post("/api/v1/events/", json=future_event_payload("Свадьба"), headers=auth_headers(token))
    event_id = r.json()["id"]
    await client.post(f"/api/v1/events/{event_id}/activate", headers=auth_headers(token))
    r = await client.post(f"/api/v1/events/{event_id}/public-share/enable", headers=auth_headers(token))
    assert r.status_code == 409


async def test_collection_public_link_returns_only_own_frames(client: AsyncClient) -> None:
    owner_token = await authenticate(client, "share3@example.com")
    other_token = await authenticate(client, "share4@example.com")
    owner_event = await _solo(client, owner_token)
    other_r = await client.post("/api/v1/events/", json=future_event_payload("Чужое"), headers=auth_headers(other_token))
    other_event = other_r.json()["id"]

    async with SessionLocal() as s:
        owner = (await s.execute(select(User).where(User.email == "share3@example.com"))).scalar_one()
        stranger_guest = Guest(event_id=UUID(other_event), name="Чужой", guest_token=uuid4().hex, fingerprint="fp-stranger")
        own_guest = Guest(event_id=UUID(other_event), user_id=owner.id, name="Я", guest_token=uuid4().hex, fingerprint="fp-me")
        s.add_all([stranger_guest, own_guest])
        await s.commit()
        stranger_id, own_id = stranger_guest.id, own_guest.id

    mine_in_own_event = await _add_frame(UUID(owner_event), None, 3)
    foreign = await _add_frame(UUID(other_event), stranger_id, 2)
    shot_by_me_elsewhere = await _add_frame(UUID(other_event), own_id, 1)

    r = await client.post("/api/v1/collections/", json={"title": "Лучшее"}, headers=auth_headers(owner_token))
    col_id = r.json()["id"]
    async with SessionLocal() as s:
        for pos, fid in enumerate([mine_in_own_event, foreign, shot_by_me_elsewhere]):
            s.add(CollectionItem(collection_id=UUID(col_id), frame_id=fid, position=pos))
        await s.commit()

    assert (await client.get(f"/api/v1/collections/{col_id}/public-share", headers=auth_headers(owner_token))).json()["public_share_token"] is None
    en = await client.post(f"/api/v1/collections/{col_id}/public-share/enable", headers=auth_headers(owner_token))
    assert en.status_code == 200, en.text
    link = en.json()["public_share_token"]

    meta = await client.get(f"/api/v1/public/albums/{link}")
    assert meta.status_code == 200
    assert meta.json()["title"] == "Лучшее" and meta.json()["total_frames"] == 2
    frames = (await client.get(f"/api/v1/public/albums/{link}/frames")).json()["items"]
    ids = {f["id"] for f in frames}
    assert ids == {str(mine_in_own_event), str(shot_by_me_elsewhere)}

    forbidden = await client.post(f"/api/v1/collections/{col_id}/public-share/enable", headers=auth_headers(other_token))
    assert forbidden.status_code in (403, 404)

    assert (await client.delete(f"/api/v1/collections/{col_id}/public-share", headers=auth_headers(owner_token))).status_code == 204
    assert (await client.get(f"/api/v1/public/albums/{link}")).status_code == 404
