import pytest
from httpx import AsyncClient

from tests.helpers import auth_headers, authenticate, future_event_payload


async def _active_event_with_guest(client: AsyncClient, token: str) -> dict:
    created = await client.post(
        "/api/v1/events/", json=future_event_payload(), headers=auth_headers(token)
    )
    event = created.json()
    await client.post(f"/api/v1/events/{event['id']}/activate", headers=auth_headers(token))
    join = await client.post(
        "/api/v1/guest/sessions",
        json={"short_code": event["short_code"], "name": "Аня", "fingerprint": "11223344"},
    )
    assert join.status_code in (200, 201), join.text
    return event


@pytest.mark.asyncio
async def test_appearance_editable_after_guests_joined(client: AsyncClient) -> None:
    token = await authenticate(client)
    event = await _active_event_with_guest(client, token)

    resp = await client.patch(
        f"/api/v1/events/{event['id']}/settings",
        json={"qr_style": "dark", "title_font": "caveat"},
        headers=auth_headers(token),
    )
    assert resp.status_code == 200, resp.text
    settings = resp.json()["settings"]
    assert settings["qr_style"] == "dark"
    assert settings["title_font"] == "caveat"

    album = await client.get(f"/api/v1/events/{event['id']}/album", headers=auth_headers(token))
    assert album.status_code == 200, album.text
    assert album.json()["title_font"] == "caveat"


@pytest.mark.asyncio
async def test_appearance_rejects_unknown_values(client: AsyncClient) -> None:
    token = await authenticate(client)
    created = await client.post(
        "/api/v1/events/", json=future_event_payload(), headers=auth_headers(token)
    )
    event_id = created.json()["id"]
    for body in ({"qr_style": "neon"}, {"title_font": "comic-sans"}):
        resp = await client.patch(
            f"/api/v1/events/{event_id}/settings", json=body, headers=auth_headers(token)
        )
        assert resp.status_code == 422


@pytest.mark.asyncio
async def test_appearance_defaults_to_null(client: AsyncClient) -> None:
    token = await authenticate(client)
    created = await client.post(
        "/api/v1/events/", json=future_event_payload(), headers=auth_headers(token)
    )
    settings = created.json()["settings"]
    assert settings["qr_style"] is None
    assert settings["title_font"] is None
