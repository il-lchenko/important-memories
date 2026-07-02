"""Storage-expiration push notifications.

Runs once a day via ARQ cron. Finds events whose expires_at falls within
7, 3, or 1 day from now and sends FCM push to the event owner (host).
Anti-duplicate: Event.notified_7d/3d/1d flags prevent re-sending.

Deep link payload: `im://extend/{event_id}` — routed by Flutter to ExtendStorageScreen.
"""
from datetime import datetime, timedelta, timezone

from sqlalchemy import and_, or_, select

from app.core.db import SessionLocal
from app.core.logging import logger
from app.domain.models import Event, EventStatus
from app.domain.models.models import DeviceToken
from app.infra import fcm_client


# (days_before, event flag name, notification copy)
_TRIGGERS: list[tuple[int, str, tuple[str, str]]] = [
    (7, "notified_7d", ("Альбом «{title}» скоро исчезнет", "Осталось 7 дней хранения. Продлить, чтобы не потерять?")),
    (3, "notified_3d", ("⚠ Осталось 3 дня", "Альбом «{title}» — сохраните воспоминания сейчас")),
    (1, "notified_1d", ("⚠ Завтра альбом станет недоступен", "«{title}» — последний шанс продлить")),
]


async def _get_owner_tokens(session, user_id) -> list[str]:
    rows = (
        await session.execute(select(DeviceToken.token).where(DeviceToken.user_id == user_id))
    ).scalars().all()
    return list(rows)


async def _notify_bucket(session, days_before: int, flag_name: str, copy: tuple[str, str]) -> int:
    now = datetime.now(timezone.utc)
    target_from = now + timedelta(days=days_before)
    target_to = target_from + timedelta(hours=24)

    stmt = (
        select(Event)
        .where(
            Event.status.in_((EventStatus.ACTIVE, EventStatus.COMPLETED)),
            Event.expires_at.is_not(None),
            Event.expires_at >= target_from,
            Event.expires_at < target_to,
            getattr(Event, flag_name).is_(False),
        )
    )
    events = list((await session.execute(stmt)).scalars().all())

    sent = 0
    for ev in events:
        tokens = await _get_owner_tokens(session, ev.user_id)
        if not tokens:
            # No devices registered — still mark as notified so we don't retry every day.
            setattr(ev, flag_name, True)
            continue
        title_tmpl, body_tmpl = copy
        title = title_tmpl.format(title=ev.title[:60])
        body = body_tmpl.format(title=ev.title[:60])
        ok = await fcm_client.send_multicast(
            tokens=tokens,
            title=title,
            body=body,
            data={"deep_link": f"im://extend/{ev.id}", "event_id": str(ev.id), "kind": "expiring"},
        )
        setattr(ev, flag_name, True)
        sent += ok
        logger.info(
            "expiry_push_sent",
            event_id=str(ev.id),
            days_before=days_before,
            devices=len(tokens),
            delivered=ok,
        )

    await session.commit()
    return sent


async def notify_expiring_events(ctx: dict) -> None:
    """ARQ cron entry point. Runs daily at 12:00 UTC (15:00 MSK)."""
    async with SessionLocal() as session:
        totals = {}
        for days_before, flag_name, copy in _TRIGGERS:
            totals[days_before] = await _notify_bucket(session, days_before, flag_name, copy)
        logger.info("expiry_notifications_batch", totals=totals)
