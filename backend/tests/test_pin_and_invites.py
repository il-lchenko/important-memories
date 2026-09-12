"""Integration-тесты для PIN + invite + rate-limit + join_attempts stats.

Требуют работающий Postgres + Redis (см. infra/docker-compose.yml).
"""
from datetime import datetime, timedelta, timezone

import pytest
from httpx import AsyncClient

from tests.helpers import auth_headers, authenticate


def _now_event_payload(title: str = "Test event") -> dict:
    now = datetime.now(timezone.utc)
    # start_at в прошлом (5 минут назад), чтобы guest.join() не спотыкался о
    # проверку «ещё не начался». end_at — через сутки.
    return {
        "title": title,
        "start_at": (now - timedelta(minutes=5)).isoformat(),
        "end_at": (now + timedelta(days=1)).isoformat(),
        "event_type": "wedding",
    }


async def _make_active_event(client: AsyncClient, token: str) -> dict:
    create = await client.post(
        "/api/v1/events/", json=_now_event_payload(), headers=auth_headers(token)
    )
    event = create.json()
    await client.post(
        f"/api/v1/events/{event['id']}/activate", headers=auth_headers(token)
    )
    detail = await client.get(
        f"/api/v1/events/{event['id']}", headers=auth_headers(token)
    )
    return detail.json()


# ── Fingerprint validation ────────────────────────────────────────────────────


@pytest.mark.asyncio
async def test_join_rejects_non_hex_fingerprint(client: AsyncClient) -> None:
    token = await authenticate(client)
    event = await _make_active_event(client, token)
    r = await client.post(
        "/api/v1/guest/sessions",
        json={"short_code": event["short_code"], "name": "X", "fingerprint": "zzzzzzzz"},
    )
    assert r.status_code == 422, r.text


@pytest.mark.asyncio
async def test_join_rejects_too_short_fingerprint(client: AsyncClient) -> None:
    token = await authenticate(client)
    event = await _make_active_event(client, token)
    r = await client.post(
        "/api/v1/guest/sessions",
        json={"short_code": event["short_code"], "name": "X", "fingerprint": "abc"},
    )
    assert r.status_code == 422


# ── PIN set/get by owner ──────────────────────────────────────────────────────


@pytest.mark.asyncio
async def test_owner_can_set_and_get_pin(client: AsyncClient) -> None:
    token = await authenticate(client)
    event = await _make_active_event(client, token)

    # Set explicit PIN
    r = await client.patch(
        f"/api/v1/events/{event['id']}/pin",
        json={"enabled": True, "pin": "4242"},
        headers=auth_headers(token),
    )
    assert r.status_code == 200, r.text
    assert r.json() == {"pin_enabled": True, "entry_pin": "4242"}

    # Get pin
    r = await client.get(
        f"/api/v1/events/{event['id']}/pin", headers=auth_headers(token)
    )
    assert r.status_code == 200
    assert r.json()["entry_pin"] == "4242"


@pytest.mark.asyncio
async def test_pin_auto_generated_when_null(client: AsyncClient) -> None:
    token = await authenticate(client)
    event = await _make_active_event(client, token)
    r = await client.patch(
        f"/api/v1/events/{event['id']}/pin",
        json={"enabled": True, "pin": None},
        headers=auth_headers(token),
    )
    assert r.status_code == 200
    pin = r.json()["entry_pin"]
    assert pin is not None and len(pin) == 4 and pin.isdigit()


@pytest.mark.asyncio
async def test_pin_disable_clears_value(client: AsyncClient) -> None:
    token = await authenticate(client)
    event = await _make_active_event(client, token)
    await client.patch(
        f"/api/v1/events/{event['id']}/pin",
        json={"enabled": True, "pin": "1111"},
        headers=auth_headers(token),
    )
    r = await client.patch(
        f"/api/v1/events/{event['id']}/pin",
        json={"enabled": False},
        headers=auth_headers(token),
    )
    assert r.json() == {"pin_enabled": False, "entry_pin": None}


@pytest.mark.asyncio
async def test_non_owner_cannot_set_pin(client: AsyncClient) -> None:
    owner = await authenticate(client, "owner@example.com")
    event = await _make_active_event(client, owner)
    attacker = await authenticate(client, "attacker@example.com")
    r = await client.patch(
        f"/api/v1/events/{event['id']}/pin",
        json={"enabled": True, "pin": "9999"},
        headers=auth_headers(attacker),
    )
    assert r.status_code == 403


# ── PIN required flow for guest ───────────────────────────────────────────────


@pytest.mark.asyncio
async def test_guest_join_returns_pin_required(client: AsyncClient) -> None:
    token = await authenticate(client)
    event = await _make_active_event(client, token)
    await client.patch(
        f"/api/v1/events/{event['id']}/pin",
        json={"enabled": True, "pin": "1234"},
        headers=auth_headers(token),
    )
    # No pin in payload
    r = await client.post(
        "/api/v1/guest/sessions",
        json={"short_code": event["short_code"], "name": "X", "fingerprint": "11223344"},
    )
    assert r.status_code == 400
    assert r.json()["error"]["code"] == "PIN_REQUIRED"


@pytest.mark.asyncio
async def test_guest_join_bad_pin(client: AsyncClient) -> None:
    token = await authenticate(client)
    event = await _make_active_event(client, token)
    await client.patch(
        f"/api/v1/events/{event['id']}/pin",
        json={"enabled": True, "pin": "1234"},
        headers=auth_headers(token),
    )
    r = await client.post(
        "/api/v1/guest/sessions",
        json={
            "short_code": event["short_code"],
            "name": "X",
            "fingerprint": "11223344",
            "pin": "0000",
        },
    )
    assert r.status_code == 400
    assert r.json()["error"]["code"] == "BAD_PIN"


@pytest.mark.asyncio
async def test_guest_join_with_correct_pin(client: AsyncClient) -> None:
    token = await authenticate(client)
    event = await _make_active_event(client, token)
    await client.patch(
        f"/api/v1/events/{event['id']}/pin",
        json={"enabled": True, "pin": "1234"},
        headers=auth_headers(token),
    )
    r = await client.post(
        "/api/v1/guest/sessions",
        json={
            "short_code": event["short_code"],
            "name": "X",
            "fingerprint": "11223344",
            "pin": "1234",
        },
    )
    assert r.status_code == 201, r.text


@pytest.mark.asyncio
async def test_bad_pin_rate_limit_per_fingerprint(client: AsyncClient) -> None:
    token = await authenticate(client)
    event = await _make_active_event(client, token)
    await client.patch(
        f"/api/v1/events/{event['id']}/pin",
        json={"enabled": True, "pin": "1234"},
        headers=auth_headers(token),
    )
    fp = "abcdef01"
    # Лимит 5 попыток bad_pin на fingerprint. Шестая → 429.
    for i in range(5):
        r = await client.post(
            "/api/v1/guest/sessions",
            json={
                "short_code": event["short_code"],
                "name": "X",
                "fingerprint": fp,
                "pin": "0000",
            },
        )
        assert r.status_code == 400, f"#{i}: {r.text}"
    over = await client.post(
        "/api/v1/guest/sessions",
        json={
            "short_code": event["short_code"],
            "name": "X",
            "fingerprint": fp,
            "pin": "0000",
        },
    )
    assert over.status_code == 429


# ── Album cap ────────────────────────────────────────────────────────────────


@pytest.mark.asyncio
async def test_album_cap_3_per_fingerprint_per_24h(client: AsyncClient) -> None:
    """Один fingerprint не может присоединить >3 разных событий за 24ч."""
    owner = await authenticate(client, "owner@example.com")
    fp = "cafecafe"
    events = []
    for i in range(4):
        e = await _make_active_event(client, owner)
        events.append(e)
    for i in range(3):
        r = await client.post(
            "/api/v1/guest/sessions",
            json={
                "short_code": events[i]["short_code"],
                "name": "G",
                "fingerprint": fp,
            },
        )
        assert r.status_code == 201, f"#{i}: {r.text}"
    # 4-й — ALBUM_CAP
    r4 = await client.post(
        "/api/v1/guest/sessions",
        json={
            "short_code": events[3]["short_code"],
            "name": "G",
            "fingerprint": fp,
        },
    )
    assert r4.status_code == 429
    assert r4.json()["error"]["code"] == "ALBUM_CAP"


@pytest.mark.asyncio
async def test_rejoin_same_event_after_cap(client: AsyncClient) -> None:
    """Re-join уже присоединённого альбома НЕ должен блокироваться cap-ом."""
    owner = await authenticate(client, "owner@example.com")
    fp = "beefbeef"
    events = [await _make_active_event(client, owner) for _ in range(3)]
    for e in events:
        r = await client.post(
            "/api/v1/guest/sessions",
            json={"short_code": e["short_code"], "name": "G", "fingerprint": fp},
        )
        assert r.status_code == 201
    # Повторный вход в первое событие тем же fp — OK.
    r = await client.post(
        "/api/v1/guest/sessions",
        json={"short_code": events[0]["short_code"], "name": "G", "fingerprint": fp},
    )
    assert r.status_code == 201


# ── Invite tokens ────────────────────────────────────────────────────────────


@pytest.mark.asyncio
async def test_invite_bypasses_pin(client: AsyncClient) -> None:
    token = await authenticate(client)
    event = await _make_active_event(client, token)
    await client.patch(
        f"/api/v1/events/{event['id']}/pin",
        json={"enabled": True, "pin": "1234"},
        headers=auth_headers(token),
    )
    create = await client.post(
        f"/api/v1/events/{event['id']}/invites",
        json={"display_name": "Анна"},
        headers=auth_headers(token),
    )
    assert create.status_code == 201, create.text
    inv = create.json()

    # Preview
    prev = await client.get(f"/api/v1/guest/invites/{inv['token']}")
    assert prev.status_code == 200
    assert prev.json()["event_title"] == event["title"]

    # Join
    join = await client.post(
        f"/api/v1/guest/invites/{inv['token']}/join",
        json={"fingerprint": "44556677"},
    )
    assert join.status_code == 201, join.text

    # Повторное использование — 409
    again = await client.post(
        f"/api/v1/guest/invites/{inv['token']}/join",
        json={"fingerprint": "44556678"},
    )
    assert again.status_code == 409


@pytest.mark.asyncio
async def test_invite_bypasses_album_cap(client: AsyncClient) -> None:
    """Даже когда cap выбран — invite создаёт сессию."""
    owner = await authenticate(client, "owner@example.com")
    fp = "d00fd00f"
    # Забиваем cap: 3 разных события
    events = [await _make_active_event(client, owner) for _ in range(3)]
    for e in events:
        await client.post(
            "/api/v1/guest/sessions",
            json={"short_code": e["short_code"], "name": "G", "fingerprint": fp},
        )
    # 4-е событие — invite
    fourth = await _make_active_event(client, owner)
    create = await client.post(
        f"/api/v1/events/{fourth['id']}/invites",
        json={"display_name": "Anna"},
        headers=auth_headers(owner),
    )
    inv = create.json()
    r = await client.post(
        f"/api/v1/guest/invites/{inv['token']}/join",
        json={"fingerprint": fp},
    )
    assert r.status_code == 201, r.text


@pytest.mark.asyncio
async def test_non_owner_cannot_list_invites(client: AsyncClient) -> None:
    owner = await authenticate(client, "owner@example.com")
    event = await _make_active_event(client, owner)
    attacker = await authenticate(client, "attacker@example.com")
    r = await client.get(
        f"/api/v1/events/{event['id']}/invites", headers=auth_headers(attacker)
    )
    assert r.status_code == 403


# ── Join stats ───────────────────────────────────────────────────────────────


@pytest.mark.asyncio
async def test_join_stats_counts_outcomes(client: AsyncClient) -> None:
    token = await authenticate(client)
    event = await _make_active_event(client, token)
    await client.patch(
        f"/api/v1/events/{event['id']}/pin",
        json={"enabled": True, "pin": "1234"},
        headers=auth_headers(token),
    )
    # 1 успешный join
    await client.post(
        "/api/v1/guest/sessions",
        json={
            "short_code": event["short_code"],
            "name": "G",
            "fingerprint": "aaaaaaaa",
            "pin": "1234",
        },
    )
    # 2 bad_pin
    for _ in range(2):
        await client.post(
            "/api/v1/guest/sessions",
            json={
                "short_code": event["short_code"],
                "name": "G",
                "fingerprint": "bbbbbbbb",
                "pin": "0000",
            },
        )
    stats = await client.get(
        f"/api/v1/events/{event['id']}/join-stats", headers=auth_headers(token)
    )
    assert stats.status_code == 200, stats.text
    data = stats.json()
    assert data["ok"] >= 1
    assert data["bad_pin"] >= 2


@pytest.mark.asyncio
async def test_join_stats_forbidden_for_non_owner(client: AsyncClient) -> None:
    owner = await authenticate(client, "owner@example.com")
    event = await _make_active_event(client, owner)
    attacker = await authenticate(client, "attacker@example.com")
    r = await client.get(
        f"/api/v1/events/{event['id']}/join-stats", headers=auth_headers(attacker)
    )
    assert r.status_code == 403


# ── Preview endpoint exposes pin_required flag ────────────────────────────────


@pytest.mark.asyncio
async def test_event_preview_pin_required(client: AsyncClient) -> None:
    token = await authenticate(client)
    event = await _make_active_event(client, token)
    await client.patch(
        f"/api/v1/events/{event['id']}/pin",
        json={"enabled": True, "pin": "1234"},
        headers=auth_headers(token),
    )
    r = await client.get(f"/api/v1/guest/events/{event['short_code']}")
    assert r.status_code == 200
    assert r.json()["pin_required"] is True


@pytest.mark.asyncio
async def test_event_preview_pin_not_required_default(client: AsyncClient) -> None:
    token = await authenticate(client)
    event = await _make_active_event(client, token)
    r = await client.get(f"/api/v1/guest/events/{event['short_code']}")
    assert r.json()["pin_required"] is False
