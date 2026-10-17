from datetime import datetime, timezone
from io import BytesIO
from uuid import UUID, uuid4

import pytest
from httpx import AsyncClient
from PIL import Image

from app.core.db import SessionLocal
from app.domain.models import CollectionItem, Frame, FrameStatus
from app.infra import s3_client
from tests.helpers import auth_headers, authenticate


def _jpeg(color: str, size: tuple[int, int] = (3000, 2000)) -> bytes:
    buf = BytesIO()
    Image.new("RGB", size, color).save(buf, format="JPEG", quality=85)
    return buf.getvalue()


@pytest.fixture
def fake_s3(monkeypatch: pytest.MonkeyPatch) -> dict[str, bytes]:
    store: dict[str, bytes] = {}
    monkeypatch.setattr(s3_client, "upload_bytes", lambda key, data, ct: store.__setitem__(key, data))
    monkeypatch.setattr(s3_client, "delete_object", lambda key: store.pop(key, None))
    monkeypatch.setattr(s3_client, "download_bytes", lambda key: store[key])
    monkeypatch.setattr(s3_client, "presign_get", lambda key, expires_in=3600: f"http://s3.test/{key}?sig=1")
    return store


async def _solo_with_frame(client: AsyncClient, token: str, store: dict[str, bytes]) -> tuple[str, UUID]:
    r = await client.post("/api/v1/events/solo", json={"title": "Соло"}, headers=auth_headers(token))
    event_id = r.json()["id"]
    key = f"events/{event_id}/preview-{uuid4().hex[:6]}.jpg"
    store[key] = _jpeg("teal", (1600, 1200))
    async with SessionLocal() as s:
        f = Frame(
            event_id=UUID(event_id), s3_key=f"events/{event_id}/orig.jpg", preview_url=key,
            status=FrameStatus.UPLOADED, captured_at=datetime.now(timezone.utc),
        )
        s.add(f)
        await s.commit()
        return event_id, f.id


async def test_collection_cover_upload_from_frame_and_clear(client: AsyncClient, fake_s3: dict[str, bytes]) -> None:
    token = await authenticate(client, "ccover1@example.com")
    _, frame_id = await _solo_with_frame(client, token, fake_s3)
    col = (await client.post("/api/v1/collections/", json={"title": "Лето"}, headers=auth_headers(token))).json()
    cid = col["id"]
    assert col["cover_url"] is None
    async with SessionLocal() as s:
        s.add(CollectionItem(collection_id=UUID(cid), frame_id=frame_id, position=0))
        await s.commit()

    r = await client.post(f"/api/v1/collections/{cid}/cover", files={"file": ("c.jpg", _jpeg("red"), "application/octet-stream")}, headers=auth_headers(token))
    assert r.status_code == 200, r.text
    first = r.json()["cover_url"]
    assert first and "/collections/" in first
    key1 = next(k for k in fake_s3 if k.startswith("collections/"))
    assert max(Image.open(BytesIO(fake_s3[key1])).size) <= 2000

    r = await client.post(f"/api/v1/collections/{cid}/cover/from-frame", json={"frame_id": str(frame_id)}, headers=auth_headers(token))
    assert r.status_code == 200, r.text
    assert r.json()["cover_url"].split("?")[0] != first.split("?")[0]
    assert len([k for k in fake_s3 if k.startswith("collections/")]) == 1

    listed = (await client.get("/api/v1/collections/", headers=auth_headers(token))).json()["collections"][0]
    assert listed["cover_url"]

    assert (await client.delete(f"/api/v1/collections/{cid}/cover", headers=auth_headers(token))).status_code == 204
    assert (await client.get(f"/api/v1/collections/{cid}", headers=auth_headers(token))).json()["cover_url"] is None
    assert not [k for k in fake_s3 if k.startswith("collections/")]


async def test_collection_cover_from_foreign_frame_is_rejected(client: AsyncClient, fake_s3: dict[str, bytes]) -> None:
    owner = await authenticate(client, "ccover2@example.com")
    other = await authenticate(client, "ccover3@example.com")
    _, foreign_frame = await _solo_with_frame(client, other, fake_s3)
    cid = (await client.post("/api/v1/collections/", json={"title": "Чужое"}, headers=auth_headers(owner))).json()["id"]
    r = await client.post(f"/api/v1/collections/{cid}/cover/from-frame", json={"frame_id": str(foreign_frame)}, headers=auth_headers(owner))
    assert r.status_code in (403, 404)
    stranger = await client.post(f"/api/v1/collections/{cid}/cover", files={"file": ("c.jpg", _jpeg("red"), "image/jpeg")}, headers=auth_headers(other))
    assert stranger.status_code in (403, 404)
