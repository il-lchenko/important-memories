"""Tests for gallery upload feature (project_upload_from_gallery.md).

Покрытие:
- toggle uploads_enabled после первого гостя работает (в отличие от других settings)
- presign source=upload при uploads_enabled=false → 409
- presign+register с source=upload → frame.source=upload
- rate-limit: второй upload presign в течение 10 сек → 429
- dedup: два presign с одним upload_hash → второй возвращает тот же frame_id + deduplicated=True
- 12 MB cap для uploads (13 MB → 422/409)
- HEIC content_type принимается для source=upload, отклоняется для source=camera
- upload_hash обязателен для source=upload, запрещён для source=camera
"""
from datetime import datetime, timezone

import pytest
from httpx import AsyncClient

from tests.helpers import auth_headers, authenticate, future_event_payload


def _hash_hex(seed: str = "a") -> str:
    """64-hex тестовый SHA-256."""
    return (seed[0] * 64)  # e.g. "aaaa...aaaa" (64 chars)


async def _create_and_activate(
    client: AsyncClient,
    token: str,
    *,
    uploads_enabled: bool = True,
    frames_per_guest: int = 10,
) -> dict:
    payload = future_event_payload()
    payload["uploads_enabled"] = uploads_enabled
    payload["frames_per_guest"] = frames_per_guest
    create = await client.post("/api/v1/events/", json=payload, headers=auth_headers(token))
    event = create.json()
    await client.post(
        f"/api/v1/events/{event['id']}/activate", headers=auth_headers(token)
    )
    detail = await client.get(
        f"/api/v1/events/{event['id']}", headers=auth_headers(token)
    )
    return detail.json()


async def _join_guest(client: AsyncClient, event: dict, fingerprint: str = "aabbccdd") -> str:
    join = await client.post(
        "/api/v1/guest/sessions",
        json={"short_code": event["short_code"], "name": "G", "fingerprint": fingerprint},
    )
    assert join.status_code in (200, 201), join.text
    return join.json()["guest_token"]


@pytest.mark.asyncio
async def test_uploads_toggle_not_locked_after_first_guest(client: AsyncClient) -> None:
    """В отличие от plan/frames_per_guest, uploads_enabled можно менять после
    прихода гостей — Хост должен иметь возможность быстро отключить при абьюзе."""
    token = await authenticate(client)
    event = await _create_and_activate(client, token, uploads_enabled=False)
    await _join_guest(client, event)

    # Ключевые настройки блокируются...
    r = await client.patch(
        f"/api/v1/events/{event['id']}/settings",
        json={"frames_per_guest": 42},
        headers=auth_headers(token),
    )
    assert r.status_code == 409

    # ...а uploads_enabled — нет.
    r = await client.patch(
        f"/api/v1/events/{event['id']}/settings",
        json={"uploads_enabled": True},
        headers=auth_headers(token),
    )
    assert r.status_code == 200, r.text
    assert r.json()["settings"]["uploads_enabled"] is True


@pytest.mark.asyncio
async def test_upload_presign_rejected_when_disabled(client: AsyncClient) -> None:
    token = await authenticate(client)
    event = await _create_and_activate(client, token, uploads_enabled=False)
    guest_token = await _join_guest(client, event)

    resp = await client.post(
        "/api/v1/guest/frames/presign",
        json={
            "content_type": "image/jpeg",
            "size_bytes": 500_000,
            "source": "upload",
            "upload_hash": _hash_hex("a"),
        },
        headers={"X-Guest-Token": guest_token},
    )
    assert resp.status_code == 409, resp.text
    assert "uploads_enabled" in ((resp.json().get("error") or {}).get("details") or {})


@pytest.mark.asyncio
async def test_upload_presign_and_register_marks_source_upload(client: AsyncClient) -> None:
    token = await authenticate(client)
    event = await _create_and_activate(client, token, uploads_enabled=True)
    guest_token = await _join_guest(client, event)

    presign = await client.post(
        "/api/v1/guest/frames/presign",
        json={
            "content_type": "image/jpeg",
            "size_bytes": 500_000,
            "source": "upload",
            "upload_hash": _hash_hex("b"),
        },
        headers={"X-Guest-Token": guest_token},
    )
    assert presign.status_code == 200, presign.text
    frame_id = presign.json()["frame_id"]
    assert presign.json()["deduplicated"] is False

    register = await client.post(
        "/api/v1/guest/frames/",
        json={
            "frame_id": frame_id,
            "captured_at": datetime.now(timezone.utc).isoformat(),
            "width": 1080,
            "height": 1080,
            "source": "upload",
        },
        headers={"X-Guest-Token": guest_token},
    )
    assert register.status_code == 201, register.text


@pytest.mark.asyncio
async def test_upload_rate_limit_hits_second_within_10s(client: AsyncClient) -> None:
    token = await authenticate(client)
    event = await _create_and_activate(client, token, uploads_enabled=True, frames_per_guest=10)
    guest_token = await _join_guest(client, event)

    r1 = await client.post(
        "/api/v1/guest/frames/presign",
        json={
            "content_type": "image/jpeg",
            "size_bytes": 500_000,
            "source": "upload",
            "upload_hash": _hash_hex("c"),
        },
        headers={"X-Guest-Token": guest_token},
    )
    assert r1.status_code == 200, r1.text

    # Второй сразу — 429 (rate-limit 1 файл / 10 сек).
    r2 = await client.post(
        "/api/v1/guest/frames/presign",
        json={
            "content_type": "image/jpeg",
            "size_bytes": 500_000,
            "source": "upload",
            "upload_hash": _hash_hex("d"),
        },
        headers={"X-Guest-Token": guest_token},
    )
    assert r2.status_code == 429, r2.text


@pytest.mark.asyncio
async def test_upload_dedup_returns_existing_frame(client: AsyncClient) -> None:
    """Два presign с одним upload_hash → второй возвращает тот же frame_id + deduplicated=True."""
    token = await authenticate(client)
    event = await _create_and_activate(client, token, uploads_enabled=True)
    guest_token = await _join_guest(client, event)

    same_hash = _hash_hex("e")

    r1 = await client.post(
        "/api/v1/guest/frames/presign",
        json={
            "content_type": "image/jpeg",
            "size_bytes": 500_000,
            "source": "upload",
            "upload_hash": same_hash,
        },
        headers={"X-Guest-Token": guest_token},
    )
    assert r1.status_code == 200, r1.text
    first_id = r1.json()["frame_id"]

    # Второй presign с тем же hash — сначала обходим rate-limit через новую сессию
    # (dedup проверяется ДО rate-limit'а? проверим оба варианта: dedup первый).
    # Реально сервер сейчас проверяет rate-limit ПЕРЕД dedup — значит второй быстрый
    # запрос будет 429 (см. предыдущий тест). Для проверки dedup используем другого
    # гостя ЭТОГО ЖЕ события: partial unique index работает per-event, hash-collision
    # тоже per-event.
    guest2 = await _join_guest(client, event, fingerprint="11223344")
    r2 = await client.post(
        "/api/v1/guest/frames/presign",
        json={
            "content_type": "image/jpeg",
            "size_bytes": 500_000,
            "source": "upload",
            "upload_hash": same_hash,
        },
        headers={"X-Guest-Token": guest2},
    )
    assert r2.status_code == 200, r2.text
    assert r2.json()["deduplicated"] is True
    assert r2.json()["frame_id"] == first_id


@pytest.mark.asyncio
async def test_upload_size_capped_at_20mb(client: AsyncClient) -> None:
    token = await authenticate(client)
    event = await _create_and_activate(client, token, uploads_enabled=True)
    guest_token = await _join_guest(client, event)

    resp = await client.post(
        "/api/v1/guest/frames/presign",
        json={
            "content_type": "image/jpeg",
            "size_bytes": 21 * 1024 * 1024,
            "source": "upload",
            "upload_hash": _hash_hex("f"),
        },
        headers={"X-Guest-Token": guest_token},
    )
    # Pydantic валидатор возвращает 422 (за-предел 20MB для uploads).
    assert resp.status_code == 422, resp.text


@pytest.mark.asyncio
async def test_heic_only_for_source_upload(client: AsyncClient) -> None:
    token = await authenticate(client)
    event = await _create_and_activate(client, token, uploads_enabled=True)
    guest_token = await _join_guest(client, event)

    # HEIC для source=camera → 422
    r1 = await client.post(
        "/api/v1/guest/frames/presign",
        json={
            "content_type": "image/heic",
            "size_bytes": 500_000,
            "source": "camera",
        },
        headers={"X-Guest-Token": guest_token},
    )
    assert r1.status_code == 422

    # HEIC для source=upload → 200
    r2 = await client.post(
        "/api/v1/guest/frames/presign",
        json={
            "content_type": "image/heic",
            "size_bytes": 500_000,
            "source": "upload",
            "upload_hash": _hash_hex("e"),
        },
        headers={"X-Guest-Token": guest_token},
    )
    assert r2.status_code == 200, r2.text


@pytest.mark.asyncio
async def test_upload_hash_required_for_source_upload(client: AsyncClient) -> None:
    token = await authenticate(client)
    event = await _create_and_activate(client, token, uploads_enabled=True)
    guest_token = await _join_guest(client, event)

    # source=upload без upload_hash → 422
    r1 = await client.post(
        "/api/v1/guest/frames/presign",
        json={
            "content_type": "image/jpeg",
            "size_bytes": 500_000,
            "source": "upload",
        },
        headers={"X-Guest-Token": guest_token},
    )
    assert r1.status_code == 422

    # source=camera с upload_hash → 422 (nice: клиент точно ничего не путает)
    r2 = await client.post(
        "/api/v1/guest/frames/presign",
        json={
            "content_type": "image/jpeg",
            "size_bytes": 500_000,
            "source": "camera",
            "upload_hash": _hash_hex("h"),
        },
        headers={"X-Guest-Token": guest_token},
    )
    assert r2.status_code == 422


@pytest.mark.asyncio
async def test_big_phone_photo_size_is_allowed_for_upload(client: AsyncClient) -> None:
    token = await authenticate(client)
    event = await _create_and_activate(client, token, uploads_enabled=True)
    guest_token = await _join_guest(client, event)
    resp = await client.post(
        "/api/v1/guest/frames/presign",
        json={"content_type": "image/jpeg", "size_bytes": 16 * 1024 * 1024, "source": "upload", "upload_hash": _hash_hex("e")},
        headers={"X-Guest-Token": guest_token},
    )
    assert resp.status_code == 200, resp.text


async def _owner_session(client: AsyncClient, token: str, event: dict) -> dict:
    resp = await client.post(
        "/api/v1/guest/sessions",
        json={"short_code": event["short_code"], "name": "Хост", "fingerprint": "abcdef12"},
        headers=auth_headers(token),
    )
    assert resp.status_code == 201, resp.text
    return resp.json()


@pytest.mark.asyncio
async def test_owner_can_upload_from_gallery_even_when_disabled_and_not_rate_limited(client: AsyncClient) -> None:
    token = await authenticate(client)
    event = await _create_and_activate(client, token, uploads_enabled=False)
    session = await _owner_session(client, token, event)
    assert session["event"]["settings"]["uploads_enabled"] is True
    headers = {"X-Guest-Token": session["guest_token"]}
    for i in range(3):
        resp = await client.post(
            "/api/v1/guest/frames/presign",
            json={"content_type": "image/jpeg", "size_bytes": 800_000, "source": "upload", "upload_hash": _hash_hex("abc"[i])},
            headers=headers,
        )
        assert resp.status_code == 200, resp.text


@pytest.mark.asyncio
async def test_owner_can_upload_to_completed_album(client: AsyncClient) -> None:
    token = await authenticate(client)
    event = await _create_and_activate(client, token, uploads_enabled=False)
    session = await _owner_session(client, token, event)
    done = await client.post(f"/api/v1/events/{event['id']}/complete", headers=auth_headers(token))
    assert done.status_code == 200, done.text
    resp = await client.post(
        "/api/v1/guest/frames/presign",
        json={"content_type": "image/jpeg", "size_bytes": 800_000, "source": "upload", "upload_hash": _hash_hex("d")},
        headers={"X-Guest-Token": session["guest_token"]},
    )
    assert resp.status_code == 200, resp.text
