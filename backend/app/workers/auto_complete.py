"""Автозавершение событий: по end_at и по наступлению отложенной проявки.

Каждую минуту сканирует ACTIVE события, у которых end_at <= now (UTC) либо
reveal_mode=delayed и reveal_at <= now, и переводит их в COMPLETED. Для проявки
хосту уходит пуш. Это единственный гарантированный путь: отложенные ARQ-задачи
ставятся только при правке настроек и теряются при черновике, оплате и рестартах.

Открытая ссылка (public_share_token) ЗДЕСЬ НЕ ГЕНЕРИРУЕТСЯ — это отдельное
явное действие Хоста через POST /events/{id}/public-share/enable.
"""

from datetime import datetime, timezone

from sqlalchemy import select
from sqlalchemy.orm import selectinload

from app.core.db import SessionLocal
from app.core.logging import logger
from app.domain.models import Event, EventStatus
from app.infra import fcm_client
from app.repos import device_repo
from app.services.event_lifecycle import completion_due, reveal_is_due


async def auto_complete_expired_events(ctx: dict) -> None:
    """ARQ cron entry point. Runs every minute."""
    async with SessionLocal() as session:
        now = datetime.now(timezone.utc)
        stmt = (
            select(Event)
            .options(selectinload(Event.settings))
            .where(Event.status == EventStatus.ACTIVE)
        )
        events = [e for e in (await session.execute(stmt)).scalars().all() if completion_due(e, now)]
        if not events:
            return

        revealed = [(e.id, e.user_id, e.title) for e in events if reveal_is_due(e, now)]
        for ev in events:
            ev.status = EventStatus.COMPLETED

        await session.commit()
        logger.info(
            "auto_completed_events",
            count=len(events),
            event_ids=[str(e.id) for e in events],
        )

        for event_id, user_id, title in revealed:
            try:
                tokens = await device_repo.get_tokens_for_user(session, user_id)
                if tokens:
                    await fcm_client.send_multicast(
                        tokens=tokens,
                        title=title,
                        body="Альбом проявлен — гости уже могут его смотреть!",
                        data={"event_id": str(event_id), "type": "album_revealed"},
                    )
            except Exception:
                logger.warning("reveal_notify_failed", event_id=str(event_id))
