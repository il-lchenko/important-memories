"""Тесты новых endpoints/функций из сессии 2026-09-20:
- POST /events/{id}/public-share/enable — Хост явно создаёт открытую ссылку
- DELETE /events/{id}/public-share — Хост отключает (SET NULL)
- GET /events/{id}/public-share — возвращает NULL если не создавали
- anonymize_guest() — обезличивание Гостя (Frame.guest_id → NULL, автор → «Гость»)
"""
from datetime import datetime, timezone
from uuid import UUID

import pytest
from httpx import AsyncClient
from sqlalchemy import select

from app.core.db import SessionLocal
from app.domain.models import Event, Frame, FrameStatus, Guest
from app.domain.models.models import ConsentRecord
from app.services.guest_service import anonymize_guest
from tests.helpers import auth_headers, authenticate, future_event_payload


# ── helpers ──────────────────────────────────────────────────────────────────
async def _create_active_completed_event(client: AsyncClient, token: str) -> dict:
    """Создаёт event, активирует, завершает — public_share доступен."""
    create = await client.post(
        "/api/v1/events/", json=future_event_payload(), headers=auth_headers(token)
    )
    event = create.json()
    await client.post(f"/api/v1/events/{event['id']}/activate", headers=auth_headers(token))
    await client.post(f"/api/v1/events/{event['id']}/complete", headers=auth_headers(token))
    return event


async def _seed_uploaded_frame_for_guest(guest_id: UUID, event_id: UUID) -> UUID:
    async with SessionLocal() as s:
        frame = Frame(
            event_id=event_id,
            guest_id=guest_id,
            s3_key=f"events/{event_id}/frames/x.jpg",
            status=FrameStatus.UPLOADED,
            captured_at=datetime.now(timezone.utc),
            caption="Красиво!",
            voice_s3_key=f"events/{event_id}/voices/x.webm",
            voice_duration_ms=1200,
            voice_peaks=[0.1, 0.5, 0.3],
        )
        s.add(frame)
        await s.commit()
        return frame.id


# ── public share ─────────────────────────────────────────────────────────────
@pytest.mark.asyncio
async def test_get_public_share_returns_null_when_not_enabled(client: AsyncClient) -> None:
    """Токен НЕ создаётся автоматически при COMPLETED — только явным enable."""
    token = await authenticate(client)
    event = await _create_active_completed_event(client, token)

    resp = await client.get(
        f"/api/v1/events/{event['id']}/public-share", headers=auth_headers(token)
    )
    assert resp.status_code == 200
    assert resp.json()["public_share_token"] is None


@pytest.mark.asyncio
async def test_enable_public_share_creates_token(client: AsyncClient) -> None:
    token = await authenticate(client)
    event = await _create_active_completed_event(client, token)

    resp = await client.post(
        f"/api/v1/events/{event['id']}/public-share/enable", headers=auth_headers(token)
    )
    assert resp.status_code == 200
    share_token = resp.json()["public_share_token"]
    assert share_token and len(share_token) > 20

    # Второй enable возвращает тот же токен (идемпотентно).
    resp2 = await client.post(
        f"/api/v1/events/{event['id']}/public-share/enable", headers=auth_headers(token)
    )
    assert resp2.json()["public_share_token"] == share_token


@pytest.mark.asyncio
async def test_disable_public_share_invalidates_token(client: AsyncClient) -> None:
    token = await authenticate(client)
    event = await _create_active_completed_event(client, token)

    # Создаём
    enable = await client.post(
        f"/api/v1/events/{event['id']}/public-share/enable", headers=auth_headers(token)
    )
    share_token = enable.json()["public_share_token"]

    # Публичный альбом работает
    public = await client.get(f"/api/v1/public/albums/{share_token}")
    assert public.status_code == 200

    # Отключаем
    delete = await client.delete(
        f"/api/v1/events/{event['id']}/public-share", headers=auth_headers(token)
    )
    assert delete.status_code == 204

    # Публичный альбом больше не отдаётся
    public_after = await client.get(f"/api/v1/public/albums/{share_token}")
    assert public_after.status_code == 404

    # GET возвращает null
    get_resp = await client.get(
        f"/api/v1/events/{event['id']}/public-share", headers=auth_headers(token)
    )
    assert get_resp.json()["public_share_token"] is None


@pytest.mark.asyncio
async def test_enable_public_share_rejected_for_non_completed(client: AsyncClient) -> None:
    """Только COMPLETED/CANCELLED события позволяют enable."""
    token = await authenticate(client)
    create = await client.post(
        "/api/v1/events/", json=future_event_payload(), headers=auth_headers(token)
    )
    event = create.json()
    await client.post(f"/api/v1/events/{event['id']}/activate", headers=auth_headers(token))
    # НЕ вызываем complete — статус ACTIVE.

    resp = await client.post(
        f"/api/v1/events/{event['id']}/public-share/enable", headers=auth_headers(token)
    )
    assert resp.status_code == 409


@pytest.mark.asyncio
async def test_public_share_not_auto_generated_on_complete(client: AsyncClient) -> None:
    """Регрессия: раньше автогенерация в event_service._auto_complete_if_expired,
    complete_event, reveal_event, list_events. Теперь — только через enable."""
    token = await authenticate(client)
    event = await _create_active_completed_event(client, token)

    async with SessionLocal() as s:
        db_event = (
            await s.execute(select(Event).where(Event.id == UUID(event["id"])))
        ).scalar_one()
        assert db_event.public_share_token is None


# ── anonymize_guest ──────────────────────────────────────────────────────────
@pytest.mark.asyncio
async def test_anonymize_guest_keeps_frame_but_nulls_guest_id(client: AsyncClient) -> None:
    """Ключевое обещание privacy v2.2 §10 п.4: файлы остаются, автор → «Гость»."""
    token = await authenticate(client)
    create = await client.post(
        "/api/v1/events/", json=future_event_payload(), headers=auth_headers(token)
    )
    event = create.json()
    await client.post(f"/api/v1/events/{event['id']}/activate", headers=auth_headers(token))

    join = await client.post(
        "/api/v1/guest/sessions",
        json={"short_code": event["short_code"], "name": "Аня", "fingerprint": "aabbccdd"},
    )
    guest_token = join.json()["guest_token"]

    # Находим guest_id и создаём frame
    async with SessionLocal() as s:
        guest = (
            await s.execute(select(Guest).where(Guest.guest_token == guest_token))
        ).scalar_one()
        guest_id = guest.id
        event_id = guest.event_id

    frame_id = await _seed_uploaded_frame_for_guest(guest_id, event_id)

    # Обезличиваем
    async with SessionLocal() as s:
        result = await anonymize_guest(s, guest_id)
    assert result["frames_anonymized"] == 1
    assert result["voice_files_deleted"] == 1

    # Проверяем состояние БД
    async with SessionLocal() as s:
        # Guest удалён
        guest_after = await s.get(Guest, guest_id)
        assert guest_after is None

        # Frame остался, guest_id = NULL, caption/voice очищены
        frame = await s.get(Frame, frame_id)
        assert frame is not None
        assert frame.guest_id is None
        assert frame.caption is None
        assert frame.voice_s3_key is None
        assert frame.voice_duration_ms is None
        assert frame.voice_peaks is None


@pytest.mark.asyncio
async def test_anonymize_guest_scrubs_consent_records(client: AsyncClient) -> None:
    """ConsentRecord для этого Гостя обезличивается: fingerprint/ip/UA → NULL."""
    token = await authenticate(client)
    create = await client.post(
        "/api/v1/events/", json=future_event_payload(), headers=auth_headers(token)
    )
    event = create.json()
    await client.post(f"/api/v1/events/{event['id']}/activate", headers=auth_headers(token))

    # Guest принимает согласие ДО join (с fingerprint)
    await client.post(
        "/api/v1/guest/consent",
        json={"doc_type": "privacy", "doc_version": "2.2", "fingerprint": "aabbccddeeff"},
    )

    # Затем join
    join = await client.post(
        "/api/v1/guest/sessions",
        json={"short_code": event["short_code"], "name": "Гость", "fingerprint": "aabbccddeeff"},
    )
    guest_token = join.json()["guest_token"]

    async with SessionLocal() as s:
        guest = (
            await s.execute(select(Guest).where(Guest.guest_token == guest_token))
        ).scalar_one()
        guest_id = guest.id

    async with SessionLocal() as s:
        await anonymize_guest(s, guest_id)

    # ConsentRecord: guest_id обнулился каскадом, fingerprint_hash/ip_hash/UA обнулены нашим кодом
    async with SessionLocal() as s:
        records = list(
            (await s.execute(select(ConsentRecord).where(ConsentRecord.doc_type == "privacy"))).scalars().all()
        )
        # Записи не удаляются полностью — audit trail сохраняется,
        # но все идентификаторы обнулены.
        for r in records:
            assert r.guest_id is None
            assert r.fingerprint_hash is None
            assert r.ip_hash is None
            assert r.user_agent is None


@pytest.mark.asyncio
async def test_album_shows_gost_for_anonymized_frame(client: AsyncClient) -> None:
    """После обезличивания фрейм в альбоме отображается с именем «Гость»
    (outerjoin + fallback в album_service)."""
    token = await authenticate(client)
    create = await client.post(
        "/api/v1/events/", json=future_event_payload(), headers=auth_headers(token)
    )
    event = create.json()
    await client.post(f"/api/v1/events/{event['id']}/activate", headers=auth_headers(token))

    join = await client.post(
        "/api/v1/guest/sessions",
        json={"short_code": event["short_code"], "name": "Настоящее имя", "fingerprint": "aabbccdd"},
    )
    guest_token = join.json()["guest_token"]

    async with SessionLocal() as s:
        guest = (
            await s.execute(select(Guest).where(Guest.guest_token == guest_token))
        ).scalar_one()
        guest_id, event_id = guest.id, guest.event_id

    await _seed_uploaded_frame_for_guest(guest_id, event_id)

    # Обезличиваем + завершаем событие (чтобы гости видели альбом)
    async with SessionLocal() as s:
        await anonymize_guest(s, guest_id)
    await client.post(f"/api/v1/events/{event['id']}/complete", headers=auth_headers(token))

    # Проверяем от Хоста
    album = await client.get(
        f"/api/v1/events/{event['id']}/album", headers=auth_headers(token)
    )
    assert album.status_code == 200
    items = album.json()["items"]
    assert len(items) == 1
    assert items[0]["guest_id"] is None
    assert items[0]["guest_name"] == "Гость"
    assert items[0]["guest_avatar_url"] is None
