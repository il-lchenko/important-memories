"""Storage-expiration notifications (push + email).

Runs once a day via ARQ cron. Finds events whose expires_at falls within
7, 3, or 1 day from now and notifies the event owner (host): FCM push when the
owner has registered devices, plus an email (push is a stub until FCM is set up,
so the email is the reliable channel).
Anti-duplicate: Event.notified_7d/3d/1d flags prevent re-sending.

Deep link payload: `im://extend/{event_id}` — routed by Flutter to ExtendStorageScreen.
Email links to the web host app: `{PUBLIC_PWA_BASE_URL}/app/events/{event_id}/extend`.
"""
from datetime import datetime, timedelta, timezone
from html import escape, unescape

from sqlalchemy import and_, or_, select

from app.core.config import settings
from app.core.db import SessionLocal
from app.core.logging import logger
from app.domain.models import Event, EventStatus
from app.domain.models.models import DeviceToken, User
from app.infra import fcm_client
from app.infra.smtp_client import send_email


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


def _days_word(n: int) -> str:
    return "1 день" if n == 1 else f"{n} дня" if n in (2, 3, 4) else f"{n} дней"


def _build_expiry_email(title: str, days_before: int, extend_url: str) -> tuple[str, str, str]:
    left = _days_word(days_before)
    subject = f"Альбом «{title}» хранится ещё {left}"
    text = (
        f"Срок хранения альбома «{title}» заканчивается через {left}.\n\n"
        "После этого фото и видео удаляются без возможности восстановления.\n"
        "Скачайте кадры или продлите хранение:\n"
        f"{extend_url}\n\n"
        "Если вы уже сохранили всё нужное, письмо можно проигнорировать.\n"
    )
    safe_title = escape(title)
    html = f"""
<!DOCTYPE html>
<html lang="ru">
<body style="font-family: -apple-system, Segoe UI, sans-serif; max-width: 480px; margin: 0 auto; padding: 32px; color: #1a1714;">
  <h2 style="margin: 0 0 16px;">Important Memories</h2>
  <p style="font-size: 15px; color: #4a4a4a; margin: 0 0 12px;">
    Срок хранения альбома <b>«{safe_title}»</b> заканчивается через {left}.
  </p>
  <p style="font-size: 15px; color: #4a4a4a; margin: 0 0 24px;">
    После этого фото и видео удаляются без возможности восстановления. Скачайте кадры или продлите хранение.
  </p>
  <p style="margin: 0 0 24px;">
    <a href="{escape(extend_url)}" style="display: inline-block; padding: 14px 24px; background: #c9881e; color: #fff;
       border-radius: 14px; text-decoration: none; font-weight: 600;">Продлить хранение</a>
  </p>
  <p style="font-size: 13px; color: #888; margin: 0;">
    Если вы уже сохранили всё нужное, письмо можно проигнорировать.
  </p>
</body>
</html>
""".strip()
    return subject, text, html


async def _send_expiry_email(session, ev: Event, days_before: int) -> bool:
    owner = await session.get(User, ev.user_id)
    if owner is None or not owner.email:
        return False
    base = settings.PUBLIC_PWA_BASE_URL.rstrip("/")
    subject, text, html = _build_expiry_email(unescape(ev.title)[:60], days_before, f"{base}/app/events/{ev.id}/extend")
    try:
        await send_email(to=owner.email, subject=subject, text=text, html=html)
    except Exception as exc:  # noqa: BLE001
        logger.warning("expiry_email_failed", event_id=str(ev.id), error_type=type(exc).__name__)
        return False
    return True


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
        emailed = await _send_expiry_email(session, ev, days_before)
        tokens = await _get_owner_tokens(session, ev.user_id)
        if not tokens:
            # No devices registered — still mark as notified so we don't retry every day.
            setattr(ev, flag_name, True)
            if emailed:
                sent += 1
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
