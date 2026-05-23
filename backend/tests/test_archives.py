import pytest
from httpx import AsyncClient

from tests.helpers import auth_headers, authenticate, future_event_payload


@pytest.mark.asyncio
async def test_request_download_returns_pending_job(client: AsyncClient) -> None:
    token = await authenticate(client)
    create = await client.post(
        "/api/v1/events/", json=future_event_payload(), headers=auth_headers(token)
    )
    event_id = create.json()["id"]
    resp = await client.post(
        f"/api/v1/events/{event_id}/download", headers=auth_headers(token)
    )
    assert resp.status_code == 202, resp.text
    body = resp.json()
    assert body["status"] == "pending"
    assert body["job_id"]


@pytest.mark.asyncio
async def test_download_status_for_unknown_job_returns_404(client: AsyncClient) -> None:
    token = await authenticate(client)
    create = await client.post(
        "/api/v1/events/", json=future_event_payload(), headers=auth_headers(token)
    )
    event_id = create.json()["id"]
    resp = await client.get(
        f"/api/v1/events/{event_id}/download/never_existed_job_id",
        headers=auth_headers(token),
    )
    assert resp.status_code == 404
