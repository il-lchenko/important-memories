import pytest
from httpx import AsyncClient

from app.services.event_service import price_for_guests


@pytest.mark.asyncio
async def test_pricing_catalog_public(client: AsyncClient) -> None:
    resp = await client.get("/api/v1/pricing")
    assert resp.status_code == 200, resp.text
    body = resp.json()
    tiers = {t["plan"]: t for t in body["tiers"]}
    assert tiers["free"]["price_kopecks"] == 0
    assert tiers["free"]["max_guests"] == 5
    assert tiers["p50"]["price_kopecks"] == 129000
    assert tiers["p250"]["max_guests"] == 250
    assert body["custom"]["from_guests"] == 251
    assert body["custom"]["per_guest_kopecks"] == 3000
    assert body["frames"]["extended_per_guest"] == 45
    assert {e["period"] for e in body["extend"]} == {"3m", "6m", "1y"}
    assert body["upgrade_premium"] == 1.15


def test_price_for_guests_matches_catalog() -> None:
    assert price_for_guests(5) == 0
    assert price_for_guests(6) == 24900
    assert price_for_guests(50) == 129000
    assert price_for_guests(250) == 769000
    assert price_for_guests(300) == 769000 + 50 * 3000
    assert price_for_guests(2001) == -1
