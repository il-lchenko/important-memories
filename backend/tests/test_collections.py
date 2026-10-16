from uuid import UUID, uuid4

import pytest
from httpx import AsyncClient
from sqlalchemy import update

from app.core.config import settings
from app.core.db import SessionLocal
from app.domain.models import Frame, FrameStatus
from tests.helpers import auth_headers, authenticate, fp, future_event_payload


async def _event(client: AsyncClient, token: str, title: str = "E") -> dict:
    created = await client.post("/api/v1/events/", json=future_event_payload(title), headers=auth_headers(token))
    event = created.json()
    await client.post(f"/api/v1/events/{event['id']}/activate", headers=auth_headers(token))
    detail = await client.get(f"/api/v1/events/{event['id']}", headers=auth_headers(token))
    return detail.json()


async def _frame(event_id: str, guest_id: str | None = None) -> str:
    fid = uuid4()
    async with SessionLocal() as s:
        s.add(Frame(
            id=fid, event_id=UUID(event_id), guest_id=UUID(guest_id) if guest_id else None,
            s3_key=f"events/{event_id}/frames/{fid}.jpg", size_bytes=1000, width=3000, height=4000,
            status=FrameStatus.UPLOADED,
        ))
        await s.commit()
    return str(fid)


async def _new_collection(client: AsyncClient, token: str, title: str = "Подборка") -> dict:
    resp = await client.post("/api/v1/collections/", json={"title": title}, headers=auth_headers(token))
    assert resp.status_code == 201, resp.text
    return resp.json()


@pytest.mark.asyncio
async def test_free_user_limited_to_three_collections(client: AsyncClient) -> None:
    token = await authenticate(client)
    for i in range(settings.MINI_FREE_ALBUMS):
        await _new_collection(client, token, f"A{i}")
    blocked = await client.post("/api/v1/collections/", json={"title": "ещё"}, headers=auth_headers(token))
    assert blocked.status_code == 409
    assert "mini_albums_limit" in blocked.text
    listed = await client.get("/api/v1/collections/", headers=auth_headers(token))
    assert len(listed.json()["collections"]) == settings.MINI_FREE_ALBUMS
    assert listed.json()["frames_per_album"] == settings.MINI_FREE_FRAMES_PER_ALBUM


@pytest.mark.asyncio
async def test_owner_can_add_own_event_frames_and_deleted_ones_disappear(client: AsyncClient) -> None:
    token = await authenticate(client)
    event = await _event(client, token)
    f1 = await _frame(event["id"])
    f2 = await _frame(event["id"])
    col = await _new_collection(client, token)

    added = await client.post(
        f"/api/v1/collections/{col['id']}/items", json={"frame_ids": [f1, f2]}, headers=auth_headers(token)
    )
    assert added.status_code == 200, added.text
    assert [i["id"] for i in added.json()["items"]] == [f1, f2]

    async with SessionLocal() as s:
        await s.execute(update(Frame).where(Frame.id == UUID(f1)).values(status=FrameStatus.DELETED))
        await s.commit()
    shown = await client.get(f"/api/v1/collections/{col['id']}", headers=auth_headers(token))
    assert [i["id"] for i in shown.json()["items"]] == [f2]
    assert shown.json()["unavailable_count"] == 1


@pytest.mark.asyncio
async def test_cannot_add_frames_from_strangers_album(client: AsyncClient) -> None:
    host = await authenticate(client, "host@example.com")
    other = await authenticate(client, "other@example.com")
    event = await _event(client, host)
    frame = await _frame(event["id"])
    col = await _new_collection(client, other)
    resp = await client.post(
        f"/api/v1/collections/{col['id']}/items", json={"frame_ids": [frame]}, headers=auth_headers(other)
    )
    assert resp.status_code == 403


@pytest.mark.asyncio
async def test_participant_can_use_frames_only_after_reveal(client: AsyncClient) -> None:
    host = await authenticate(client, "host@example.com")
    guest = await authenticate(client, "guest@example.com")
    event = await _event(client, host)
    join = await client.post(
        "/api/v1/guest/sessions",
        json={"short_code": event["short_code"], "name": "Гость", "fingerprint": fp("g")},
        headers=auth_headers(guest),
    )
    assert join.status_code == 201, join.text
    frame = await _frame(event["id"])
    col = await _new_collection(client, guest)

    before = await client.post(
        f"/api/v1/collections/{col['id']}/items", json={"frame_ids": [frame]}, headers=auth_headers(guest)
    )
    assert before.status_code == 403

    done = await client.post(f"/api/v1/events/{event['id']}/complete", headers=auth_headers(host))
    assert done.status_code == 200, done.text
    after = await client.post(
        f"/api/v1/collections/{col['id']}/items", json={"frame_ids": [frame]}, headers=auth_headers(guest)
    )
    assert after.status_code == 200, after.text
    assert len(after.json()["items"]) == 1


@pytest.mark.asyncio
async def test_frames_per_collection_limit(client: AsyncClient, monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(settings, "MINI_FREE_FRAMES_PER_ALBUM", 1)
    token = await authenticate(client)
    event = await _event(client, token)
    f1, f2 = await _frame(event["id"]), await _frame(event["id"])
    col = await _new_collection(client, token)
    resp = await client.post(
        f"/api/v1/collections/{col['id']}/items", json={"frame_ids": [f1, f2]}, headers=auth_headers(token)
    )
    assert resp.status_code == 409
    assert "mini_frames_limit" in resp.text


@pytest.mark.asyncio
async def test_rename_and_delete_collection(client: AsyncClient) -> None:
    token = await authenticate(client)
    col = await _new_collection(client, token)
    renamed = await client.patch(
        f"/api/v1/collections/{col['id']}", json={"title": "Новое"}, headers=auth_headers(token)
    )
    assert renamed.status_code == 204
    got = await client.get(f"/api/v1/collections/{col['id']}", headers=auth_headers(token))
    assert got.json()["title"] == "Новое"
    gone = await client.delete(f"/api/v1/collections/{col['id']}", headers=auth_headers(token))
    assert gone.status_code == 204
    again = await client.get(f"/api/v1/collections/{col['id']}", headers=auth_headers(token))
    assert again.status_code == 404
