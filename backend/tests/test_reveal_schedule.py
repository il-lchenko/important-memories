from datetime import datetime, timedelta, timezone
from uuid import UUID

from httpx import AsyncClient
from sqlalchemy import select

from app.core.db import SessionLocal
from app.domain.models import Event, EventSettings, EventStatus
from app.workers.auto_complete import auto_complete_expired_events

from .helpers import authenticate, auth_headers, future_event_payload


async def _create_active_delayed(client: AsyncClient, token: str) -> str:
    payload = future_event_payload("Delayed")
    payload["reveal_mode"] = "delayed"
    payload["reveal_at"] = (datetime.now(timezone.utc) + timedelta(hours=1)).isoformat()
    r = await client.post("/api/v1/events/", json=payload, headers=auth_headers(token))
    assert r.status_code == 201, r.text
    event_id = r.json()["id"]
    r = await client.post(f"/api/v1/events/{event_id}/activate", headers=auth_headers(token))
    assert r.status_code == 200, r.text
    return event_id


async def _move_reveal(event_id: str, delta: timedelta) -> None:
    async with SessionLocal() as s:
        st = (await s.execute(select(EventSettings).where(EventSettings.event_id == UUID(event_id)))).scalar_one()
        st.reveal_at = datetime.now(timezone.utc) + delta
        await s.commit()


async def _status(event_id: str) -> EventStatus:
    async with SessionLocal() as s:
        ev = (await s.execute(select(Event).where(Event.id == UUID(event_id)))).scalar_one()
        return ev.status


async def test_cron_completes_event_when_reveal_at_passed(client: AsyncClient) -> None:
    token = await authenticate(client)
    event_id = await _create_active_delayed(client, token)

    await auto_complete_expired_events({})
    assert await _status(event_id) == EventStatus.ACTIVE

    await _move_reveal(event_id, timedelta(seconds=-5))
    await auto_complete_expired_events({})
    assert await _status(event_id) == EventStatus.COMPLETED


async def test_instant_event_not_completed_by_cron(client: AsyncClient) -> None:
    token = await authenticate(client)
    r = await client.post("/api/v1/events/", json=future_event_payload("Instant"), headers=auth_headers(token))
    event_id = r.json()["id"]
    await client.post(f"/api/v1/events/{event_id}/activate", headers=auth_headers(token))
    await auto_complete_expired_events({})
    assert await _status(event_id) == EventStatus.ACTIVE


async def test_host_list_self_heals_after_reveal_at(client: AsyncClient) -> None:
    token = await authenticate(client)
    event_id = await _create_active_delayed(client, token)
    await _move_reveal(event_id, timedelta(seconds=-5))

    r = await client.get(f"/api/v1/events/{event_id}", headers=auth_headers(token))
    assert r.status_code == 200
    assert r.json()["status"] == "completed"
