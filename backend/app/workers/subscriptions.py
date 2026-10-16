"""Cron: автосписание подписки «Плюс» (раз в час)."""
from app.core.db import SessionLocal
from app.core.logging import logger
from app.services import subscription_service


async def renew_subscriptions(ctx: dict) -> None:
    async with SessionLocal() as session:
        stats = await subscription_service.renew_due(session)
    if any(stats.values()):
        logger.info("subscriptions_renewed", **stats)
