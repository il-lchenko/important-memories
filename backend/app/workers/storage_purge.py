"""Очистка хранилища: без неё сроки хранения тарифов не работали и S3 рос бесконечно.

1. Альбомы с истёкшим сроком хранения (не черновики) и удалённые события —
   удаляем все файлы под events/{id}/, кадры помечаем удалёнными.
2. ZIP-архивы старше 7 дней (ссылка на скачивание живёт 7 дней).
Ничего не удаляется раньше STORAGE_PURGE_NOT_BEFORE — переходный период
для альбомов, созданных до появления очистки.

Защищены навсегда: альбомы пользователей-админов и все альбомы, созданные
до PURGE_PROTECT_CREATED_BEFORE.
"""
import asyncio
from datetime import datetime, timedelta, timezone

from sqlalchemy import and_, or_, select, update

from app.core.config import settings
from app.core.db import SessionLocal
from app.core.logging import logger
from app.domain.models import Event, EventStatus, Frame, FrameStatus, User
from app.infra import s3_client

ARCHIVE_TTL = timedelta(days=7)
CANCELLED_GRACE = timedelta(days=1)


def _not_before() -> datetime:
    return datetime.fromisoformat(settings.STORAGE_PURGE_NOT_BEFORE)


def _protect_before() -> datetime:
    return datetime.fromisoformat(settings.PURGE_PROTECT_CREATED_BEFORE)


def is_protected(event: Event, owner_is_admin: bool) -> bool:
    """Альбом нельзя удалять очисткой: админский или созданный до введения сроков."""
    return owner_is_admin or event.created_at < _protect_before()


def purge_due_at(event: Event) -> datetime | None:
    """Когда файлы события можно удалять; None — пока нельзя (черновик без срока и т.п.)."""
    if event.status == EventStatus.CANCELLED:
        due = event.updated_at + CANCELLED_GRACE
    elif event.status in (EventStatus.ACTIVE, EventStatus.COMPLETED) and event.expires_at is not None:
        due = event.expires_at
    else:
        return None
    return max(due, _not_before())


async def purge_expired_events(ctx: dict) -> int:
    now = datetime.now(timezone.utc)
    if now < _not_before():
        return 0
    async with SessionLocal() as session:
        stmt = select(Event).join(User, User.id == Event.user_id).where(
            Event.storage_purged_at.is_(None),
            User.is_admin.is_(False),
            Event.created_at >= _protect_before(),
            or_(
                Event.status == EventStatus.CANCELLED,
                and_(
                    Event.status.in_((EventStatus.ACTIVE, EventStatus.COMPLETED)),
                    Event.expires_at.is_not(None),
                    Event.expires_at < now,
                ),
            ),
        )
        events = list((await session.execute(stmt)).scalars().all())
        purged = 0
        for event in events:
            due = purge_due_at(event)
            if due is None or due > now:
                continue
            removed = await asyncio.to_thread(s3_client.delete_prefix, f"events/{event.id}/")
            await session.execute(
                update(Frame)
                .where(Frame.event_id == event.id, Frame.status != FrameStatus.DELETED)
                .values(status=FrameStatus.DELETED, deleted_at=now, voice_s3_key=None)
            )
            event.cover_url = None
            event.storage_purged_at = now
            await session.commit()
            purged += 1
            logger.info("storage_event_purged", event_id=str(event.id), objects=removed)
    return purged


def _expired_archive_keys(now: datetime) -> list[str]:
    return [
        key
        for key, modified in s3_client.list_objects("events/")
        if "/archives/" in key and modified < now - ARCHIVE_TTL
    ]


async def purge_old_archives(ctx: dict) -> int:
    now = datetime.now(timezone.utc)
    keys = await asyncio.to_thread(_expired_archive_keys, now)
    if not keys:
        return 0
    removed = await asyncio.to_thread(s3_client.delete_keys, keys)
    logger.info("storage_archives_purged", objects=removed)
    return removed
