import pytest
from httpx import AsyncClient

from tests.helpers import auth_headers, authenticate, future_event_payload


@pytest.mark.asyncio
async def test_events_create_rate_limited_after_5(client: AsyncClient) -> None:
    token = await authenticate(client)
    for i in range(5):
        r = await client.post(
            "/api/v1/events/",
            json=future_event_payload(f"E{i}"),
            headers=auth_headers(token),
        )
        assert r.status_code == 201, f"#{i}: {r.text}"
    blocked = await client.post(
        "/api/v1/events/",
        json=future_event_payload("over"),
        headers=auth_headers(token),
    )
    assert blocked.status_code == 429
