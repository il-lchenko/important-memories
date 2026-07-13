from secrets import token_urlsafe
from uuid import UUID

from sqlalchemy import select
from sqlalchemy.orm import selectinload

from app.core.db import SessionLocal
from app.core.logging import logger
from app.domain.models import Event, EventStatus
from app.infra import fcm_client
from app.repos import device_repo


async def execute_reveal(ctx: dict, event_id: str) -> None:
    """Mark a delayed-reveal event as completed at its reveal_at timestamp."""
    event_uuid = UUID(event_id)
    async with SessionLocal() as session:
        event = (
            await session.execute(
                select(Event).options(selectinload(Event.settings)).where(Event.id == event_uuid)
            )
        ).scalar_one_or_none()
        if event is None:
            logger.warning("reveal_skip", event_id=event_id, reason="not_found")
            return
        if event.status != EventStatus.ACTIVE:
            logger.info(
                "reveal_skip", event_id=event_id, reason="not_active", status=event.status.value
            )
            return
        event.status = EventStatus.COMPLETED
        if event.public_share_token is None:
            event.public_share_token = token_urlsafe(24)
        await session.commit()
        logger.info("reveal_executed", event_id=event_id)

        host_tokens = await device_repo.get_tokens_for_user(session, event.user_id)
        if host_tokens:
            await fcm_client.send_multicast(
                tokens=host_tokens,
                title=event.title,
                body="Альбом проявлен — гости уже могут его смотреть!",
                data={"event_id": event_id, "type": "album_revealed"},
            )
