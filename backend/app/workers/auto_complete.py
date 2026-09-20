"""Автозавершение событий по end_at.

Каждую минуту сканирует ACTIVE события, у которых end_at <= now (UTC),
и переводит их в COMPLETED.

Открытая ссылка (public_share_token) ЗДЕСЬ НЕ ГЕНЕРИРУЕТСЯ — это отдельное
явное действие Хоста через POST /events/{id}/public-share/enable.
"""

from datetime import datetime, timezone

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

        await session.commit()
        logger.info(
            "auto_completed_events",
            count=len(events),
            event_ids=[str(e.id) for e in events],
        )
