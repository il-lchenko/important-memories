from datetime import datetime, timedelta, timezone
from io import BytesIO
from uuid import UUID

import pytest
from httpx import AsyncClient
from PIL import Image

from app.core.db import SessionLocal
from app.domain.models import Frame, FrameStatus
from app.infra import s3_client
from tests.helpers import auth_headers, authenticate, future_event_payload


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


async def _event(client: AsyncClient, token: str) -> str:
    r = await client.post("/api/v1/events/", json=future_event_payload("Обложка"), headers=auth_headers(token))
    assert r.status_code == 201, r.text
    event_id = r.json()["id"]
    r = await client.post(f"/api/v1/events/{event_id}/activate", headers=auth_headers(token))
    assert r.status_code == 200, r.text
    return event_id


async def _post_cover(client: AsyncClient, token: str, event_id: str, data: bytes):
    return await client.post(
        f"/api/v1/events/{event_id}/cover",
        files={"file": ("c.jpg", data, "image/jpeg")},
        headers=auth_headers(token),
    )


async def test_cover_can_be_replaced_many_times(client: AsyncClient, fake_s3: dict[str, bytes]) -> None:
    token = await authenticate(client, "cover1@example.com")
    event_id = await _event(client, token)

    urls = []
    for color in ("red", "green", "blue"):
        r = await _post_cover(client, token, event_id, _jpeg(color))
        assert r.status_code == 200, r.text
        urls.append(r.json()["cover_url"])

    assert len(set(u.split("?")[0] for u in urls)) == 3
    detail = await client.get(f"/api/v1/events/{event_id}", headers=auth_headers(token))
    assert detail.json()["cover_url"].split("?")[0] == urls[-1].split("?")[0]
    covers = [k for k in fake_s3 if "/cover-" in k]
    assert len(covers) == 1


async def test_cover_is_downscaled_and_large_phone_photos_accepted(client: AsyncClient, fake_s3: dict[str, bytes]) -> None:
    token = await authenticate(client, "cover2@example.com")
    event_id = await _event(client, token)
    big = _jpeg("orange", (6000, 4000))
    r = await _post_cover(client, token, event_id, big)
    assert r.status_code == 200, r.text
    key = next(k for k in fake_s3 if "/cover-" in k)
    img = Image.open(BytesIO(fake_s3[key]))
    assert max(img.size) <= 2000


async def _add_frame(event_id: str, *, rotation: int = 0, minutes_ago: int = 0, color: str = "purple") -> tuple[str, str]:
    key = f"events/{event_id}/previews/{color}-{minutes_ago}.jpg"
    async with SessionLocal() as s:
        f = Frame(
            event_id=UUID(event_id), s3_key=f"events/{event_id}/orig-{color}-{minutes_ago}.jpg", preview_url=key,
            status=FrameStatus.UPLOADED, rotation=rotation,
            captured_at=datetime.now(timezone.utc) - timedelta(minutes=minutes_ago),
        )
        s.add(f)
        await s.commit()
        return str(f.id), key


async def test_cover_from_first_frame_and_from_chosen_frame(client: AsyncClient, fake_s3: dict[str, bytes]) -> None:
    token = await authenticate(client, "cover3@example.com")
    event_id = await _event(client, token)

    r = await client.post(f"/api/v1/events/{event_id}/cover/from-frame", json={}, headers=auth_headers(token))
    assert r.status_code == 404

    _, k_old = await _add_frame(event_id, minutes_ago=10, color="red")
    fake_s3[k_old] = _jpeg("red", (1600, 1200))
    f_new, k_new = await _add_frame(event_id, minutes_ago=1, color="blue", rotation=90)
    fake_s3[k_new] = _jpeg("blue", (1600, 1200))

    r = await client.post(f"/api/v1/events/{event_id}/cover/from-frame", json={}, headers=auth_headers(token))
    assert r.status_code == 200, r.text
    first_key = next(k for k in fake_s3 if "/cover-" in k)
    assert Image.open(BytesIO(fake_s3[first_key])).size == (1600, 1200)

    r = await client.post(f"/api/v1/events/{event_id}/cover/from-frame", json={"frame_id": f_new}, headers=auth_headers(token))
    assert r.status_code == 200, r.text
    covers = [k for k in fake_s3 if "/cover-" in k]
    assert len(covers) == 1 and covers[0] != first_key
    assert Image.open(BytesIO(fake_s3[covers[0]])).size == (1200, 1600)


async def test_cover_from_frame_requires_owner(client: AsyncClient, fake_s3: dict[str, bytes]) -> None:
    owner = await authenticate(client, "cover4@example.com")
    event_id = await _event(client, owner)
    other = await authenticate(client, "cover5@example.com")
    r = await client.post(f"/api/v1/events/{event_id}/cover/from-frame", json={}, headers=auth_headers(other))
    assert r.status_code in (403, 404)


async def test_cover_accepts_octet_stream_from_mobile_client(client: AsyncClient, fake_s3: dict[str, bytes]) -> None:
    token = await authenticate(client, "cover6@example.com")
    event_id = await _event(client, token)
    r = await client.post(
        f"/api/v1/events/{event_id}/cover",
        files={"file": ("cover.jpg", _jpeg("teal"), "application/octet-stream")},
        headers=auth_headers(token),
    )
    assert r.status_code == 200, r.text

    r = await client.post(
        f"/api/v1/events/{event_id}/cover",
        files={"file": ("cover.jpg", b"not an image", "application/octet-stream")},
        headers=auth_headers(token),
    )
    assert r.status_code == 409
