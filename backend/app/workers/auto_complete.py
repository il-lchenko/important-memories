"""Автозавершение событий по end_at.

Каждую минуту сканирует ACTIVE события, у которых end_at <= now (UTC),
переводит их в COMPLETED и генерит public_share_token, если он ещё не задан.

Дублирует self-healing логику из event_service/guest_service, но независимо
от того, обращается ли кто-нибудь к событию через API. Раньше событие могло
остаться ACTIVE навсегда, если после end_at никто не открыл его.
"""

from datetime import datetime, timezone
from secrets import token_urlsafe

from sqlalchemy import select

from app.core.db import SessionLocal
from app.core.logging import logger
from app.domain.models import Event, EventStatus


async def auto_complete_expired_events(ctx: dict) -> None:
    """ARQ cron entry point. Runs every minute."""
    async with SessionLocal() as session:
        now = datetime.now(timezone.utc)
        stmt = select(Event).where(
            Event.status == EventStatus.ACTIVE,
            Event.end_at.is_not(None),
            Event.end_at <= now,
        )
        events = list((await session.execute(stmt)).scalars().all())
        if not events:
            return

        for ev in events:
            ev.status = EventStatus.COMPLETED
            if ev.public_share_token is None:
                ev.public_share_token = token_urlsafe(24)

        await session.commit()
        logger.info(
            "auto_completed_events",
            count=len(events),
            event_ids=[str(e.id) for e in events],
        )
