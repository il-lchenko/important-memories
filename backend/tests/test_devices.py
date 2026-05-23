import pytest
from httpx import AsyncClient

from tests.helpers import auth_headers, authenticate


@pytest.mark.asyncio
async def test_register_device(client: AsyncClient) -> None:
    token = await authenticate(client)
    resp = await client.post(
        "/api/v1/devices/",
        json={"platform": "ios", "token": "apns-token-abcdef"},
        headers=auth_headers(token),
    )
    assert resp.status_code == 201, resp.text
    body = resp.json()
    assert body["platform"] == "ios"


@pytest.mark.asyncio
async def test_register_device_upserts_on_same_token(client: AsyncClient) -> None:
    token = await authenticate(client)
    first = await client.post(
        "/api/v1/devices/",
        json={"platform": "android", "token": "fcm-12345"},
        headers=auth_headers(token),
    )
    second = await client.post(
        "/api/v1/devices/",
        json={"platform": "android", "token": "fcm-12345"},
        headers=auth_headers(token),
    )
    assert first.json()["id"] == second.json()["id"]


@pytest.mark.asyncio
async def test_register_device_requires_auth(client: AsyncClient) -> None:
    resp = await client.post(
        "/api/v1/devices/", json={"platform": "ios", "token": "abc12345"}
    )
    assert resp.status_code == 401
