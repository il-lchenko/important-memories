from datetime import datetime, timedelta, timezone
from uuid import UUID

import pytest
from httpx import AsyncClient
from sqlalchemy import select

from app.core.db import SessionLocal
from app.domain.models import Event
from app.workers import notifications
from app.workers.notifications import notify_expiring_events

from .helpers import auth_headers, authenticate, future_event_payload


async def _active_event(client: AsyncClient, token: str, title: str) -> str:
    r = await client.post("/api/v1/events/", json=future_event_payload(title), headers=auth_headers(token))
    assert r.status_code == 201, r.text
    event_id = r.json()["id"]
    r = await client.post(f"/api/v1/events/{event_id}/activate", headers=auth_headers(token))
    assert r.status_code == 200, r.text
    return event_id


async def _set_expiry(event_id: str, delta: timedelta) -> None:
    async with SessionLocal() as s:
        ev = (await s.execute(select(Event).where(Event.id == UUID(event_id)))).scalar_one()
        ev.expires_at = datetime.now(timezone.utc) + delta
        await s.commit()


async def _flags(event_id: str) -> tuple[bool, bool, bool]:
    async with SessionLocal() as s:
        ev = (await s.execute(select(Event).where(Event.id == UUID(event_id)))).scalar_one()
        return ev.notified_7d, ev.notified_3d, ev.notified_1d


@pytest.fixture
def sent(monkeypatch: pytest.MonkeyPatch) -> list[dict]:
    box: list[dict] = []

    async def fake_send(to: str, subject: str, text: str, html: str | None = None) -> None:
        box.append({"to": to, "subject": subject, "text": text, "html": html})

    monkeypatch.setattr(notifications, "send_email", fake_send)
    return box


async def test_email_reminder_7_days_sent_once(client: AsyncClient, sent: list[dict]) -> None:
    token = await authenticate(client, "owner@example.com")
    event_id = await _active_event(client, token, "Свадьба <Ани>")
    await _set_expiry(event_id, timedelta(days=7, hours=6))

    await notify_expiring_events({})

    assert len(sent) == 1
    mail = sent[0]
    assert mail["to"] == "owner@example.com"
    assert "7 дней" in mail["subject"]
    assert f"/app/events/{event_id}/extend" in mail["text"]
    assert "&lt;Ани&gt;" in mail["html"]
    assert await _flags(event_id) == (True, False, False)

    await notify_expiring_events({})
    assert len(sent) == 1


async def test_email_reminder_buckets_3_and_1(client: AsyncClient, sent: list[dict]) -> None:
    token = await authenticate(client, "owner2@example.com")
    e3 = await _active_event(client, token, "Три дня")
    e1 = await _active_event(client, token, "Один день")
    await _set_expiry(e3, timedelta(days=3, hours=5))
    await _set_expiry(e1, timedelta(days=1, hours=5))

    await notify_expiring_events({})

    subjects = sorted(m["subject"] for m in sent)
    assert any("3 дня" in s for s in subjects)
    assert any("1 день" in s for s in subjects)
    assert await _flags(e3) == (False, True, False)
    assert await _flags(e1) == (False, False, True)


async def test_email_failure_does_not_break_the_run(client: AsyncClient, monkeypatch: pytest.MonkeyPatch) -> None:
    async def boom(**_: object) -> None:
        raise RuntimeError("smtp down")

    monkeypatch.setattr(notifications, "send_email", boom)
    token = await authenticate(client, "owner3@example.com")
    event_id = await _active_event(client, token, "Сбой почты")
    await _set_expiry(event_id, timedelta(days=7, hours=2))

    await notify_expiring_events({})

    assert await _flags(event_id) == (True, False, False)
