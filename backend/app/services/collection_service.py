"""Мини-альбомы: подборки ссылок на кадры из разных альбомов пользователя.

Файлы не копируются. Кадр попадает в подборку только если у пользователя уже есть
доступ к его альбому: он владелец события либо участник (гость с входом под своим
аккаунтом), а для участника альбом уже проявлен. Доступ перепроверяется при каждом
чтении, поэтому удалённый кадр, очищенный по сроку альбом или потерянный доступ
просто пропадают из подборки.
"""
from datetime import datetime, timezone
from uuid import UUID

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.core.errors import ConflictError, NotFoundError, PermissionDeniedError
from app.domain.models import (
    Collection,
    CollectionItem,
    Event,
    EventStatus,
    Frame,
    FrameStatus,
    Guest,
    User,
)
from app.domain.schemas.collections import (
    CollectionFrameOut,
    CollectionOut,
    CollectionSummaryOut,
    CollectionsListOut,
)
from app.infra import s3_client
from app.services import entitlement_service

_URL_TTL = 86400


def _revealed(event: Event) -> bool:
    if event.status in (EventStatus.COMPLETED, EventStatus.CANCELLED):
        return True
    s = event.settings
    return s is not None and s.reveal_at is not None and s.reveal_at <= datetime.now(timezone.utc)


async def _guest_event_ids(session: AsyncSession, user_id: UUID, event_ids: set[UUID]) -> set[UUID]:
    if not event_ids:
        return set()
    rows = await session.execute(
        select(Guest.event_id).where(Guest.user_id == user_id, Guest.event_id.in_(event_ids))
    )
    return {r[0] for r in rows}


def _can_see(event: Event, user_id: UUID, guest_events: set[UUID]) -> bool:
    if event.storage_purged_at is not None:
        return False
    if event.user_id == user_id:
        return True
    return event.id in guest_events and _revealed(event)


async def _user(session: AsyncSession, user_id: UUID) -> User:
    user = await session.get(User, user_id)
    if user is None:
        raise NotFoundError("User not found")
    return user


async def _owned(session: AsyncSession, user_id: UUID, collection_id: UUID) -> Collection:
    col = (
        await session.execute(
            select(Collection).options(selectinload(Collection.items)).where(Collection.id == collection_id)
        )
    ).scalar_one_or_none()
    if col is None:
        raise NotFoundError("Collection not found")
    if col.user_id != user_id:
        raise PermissionDeniedError("Not your collection")
    return col


def _frame_out(frame: Frame, event: Event, mine: bool) -> CollectionFrameOut:
    def url(key: str | None) -> str | None:
        return s3_client.presign_get(key, expires_in=_URL_TTL) if key else None

    return CollectionFrameOut(
        id=frame.id,
        event_id=event.id,
        event_title=event.title,
        captured_at=frame.captured_at,
        thumbnail_url=url(frame.thumbnail_url),
        preview_url=url(frame.preview_url),
        full_url=url(frame.s3_key) or "",
        width=frame.width,
        height=frame.height,
        rotation=frame.rotation,
        caption=frame.caption,
        is_mine=mine,
    )


async def _visible_frames(
    session: AsyncSession, user_id: UUID, frame_ids: list[UUID]
) -> dict[UUID, tuple[Frame, Event, bool]]:
    """frame_id -> (кадр, событие, снят_мной) для кадров, которые пользователь вправе видеть."""
    if not frame_ids:
        return {}
    rows = (
        await session.execute(
            select(Frame, Event)
            .join(Event, Event.id == Frame.event_id)
            .options(selectinload(Event.settings))
            .where(Frame.id.in_(frame_ids), Frame.status == FrameStatus.UPLOADED)
        )
    ).all()
    event_ids = {e.id for _, e in rows}
    guest_events = await _guest_event_ids(session, user_id, event_ids)
    my_guests = {
        r[0]
        for r in await session.execute(
            select(Guest.id).where(Guest.user_id == user_id, Guest.event_id.in_(event_ids or {UUID(int=0)}))
        )
    }
    out: dict[UUID, tuple[Frame, Event, bool]] = {}
    for frame, event in rows:
        if _can_see(event, user_id, guest_events):
            out[frame.id] = (frame, event, frame.guest_id in my_guests)
    return out


async def list_collections(session: AsyncSession, user_id: UUID) -> CollectionsListOut:
    user = await _user(session, user_id)
    limits = await entitlement_service.mini_limits(session, user)
    cols = (
        await session.execute(
            select(Collection)
            .options(selectinload(Collection.items))
            .where(Collection.user_id == user_id)
            .order_by(Collection.created_at.desc())
        )
    ).scalars().all()
    summaries: list[CollectionSummaryOut] = []
    for col in cols:
        ids = [i.frame_id for i in col.items]
        visible = await _visible_frames(session, user_id, ids)
        ordered = [visible[i][0] for i in ids if i in visible]
        previews = [
            s3_client.presign_get(f.thumbnail_url, expires_in=_URL_TTL)
            for f in ordered[:4]
            if f.thumbnail_url
        ]
        summaries.append(
            CollectionSummaryOut(
                id=col.id, title=col.title, items_count=len(ordered),
                created_at=col.created_at, preview_urls=previews,
            )
        )
    return CollectionsListOut(
        collections=summaries, albums_limit=limits.albums, frames_per_album=limits.frames_per_album
    )


async def create_collection(session: AsyncSession, user_id: UUID, title: str) -> CollectionOut:
    user = await _user(session, user_id)
    limits = await entitlement_service.mini_limits(session, user)
    if limits.albums is not None:
        count = int(
            (await session.execute(select(func.count(Collection.id)).where(Collection.user_id == user_id))).scalar_one()
        )
        if count >= limits.albums:
            raise ConflictError(
                f"Можно создать {limits.albums} мини-альбома бесплатно. Удалите ненужный или оформите «Плюс».",
                details={"reason": "mini_albums_limit", "limit": limits.albums, "used": count},
            )
    col = Collection(user_id=user_id, title=title)
    session.add(col)
    await session.commit()
    return CollectionOut(
        id=col.id, title=col.title, created_at=col.created_at, items=[],
        frames_limit=limits.frames_per_album,
    )


async def get_collection(session: AsyncSession, user_id: UUID, collection_id: UUID) -> CollectionOut:
    user = await _user(session, user_id)
    limits = await entitlement_service.mini_limits(session, user)
    col = await _owned(session, user_id, collection_id)
    ids = [i.frame_id for i in col.items]
    visible = await _visible_frames(session, user_id, ids)
    items = [_frame_out(*visible[i]) for i in ids if i in visible]
    return CollectionOut(
        id=col.id, title=col.title, created_at=col.created_at, items=items,
        frames_limit=limits.frames_per_album, unavailable_count=len(ids) - len(items),
    )


async def rename_collection(session: AsyncSession, user_id: UUID, collection_id: UUID, title: str) -> None:
    col = await _owned(session, user_id, collection_id)
    col.title = title
    await session.commit()


async def delete_collection(session: AsyncSession, user_id: UUID, collection_id: UUID) -> None:
    col = await _owned(session, user_id, collection_id)
    await session.delete(col)
    await session.commit()


async def add_items(
    session: AsyncSession, user_id: UUID, collection_id: UUID, frame_ids: list[UUID]
) -> int:
    user = await _user(session, user_id)
    limits = await entitlement_service.mini_limits(session, user)
    col = await _owned(session, user_id, collection_id)
    existing = {i.frame_id for i in col.items}
    new_ids = [f for f in dict.fromkeys(frame_ids) if f not in existing]
    if not new_ids:
        return 0
    if len(existing) + len(new_ids) > limits.frames_per_album:
        raise ConflictError(
            f"В подборке может быть до {limits.frames_per_album} кадров.",
            details={"reason": "mini_frames_limit", "limit": limits.frames_per_album, "used": len(existing)},
        )
    visible = await _visible_frames(session, user_id, new_ids)
    if len(visible) != len(new_ids):
        raise PermissionDeniedError("Часть кадров недоступна для подборки")
    position = max((i.position for i in col.items), default=-1) + 1
    for offset, fid in enumerate(new_ids):
        session.add(CollectionItem(collection_id=col.id, frame_id=fid, position=position + offset))
    await session.commit()
    return len(new_ids)


async def remove_item(session: AsyncSession, user_id: UUID, collection_id: UUID, frame_id: UUID) -> None:
    col = await _owned(session, user_id, collection_id)
    for item in col.items:
        if item.frame_id == frame_id:
            await session.delete(item)
    await session.commit()


async def get_public_share(session: AsyncSession, user_id: UUID, collection_id: UUID) -> str | None:
    return (await _owned(session, user_id, collection_id)).public_share_token


async def enable_public_share(session: AsyncSession, user_id: UUID, collection_id: UUID) -> str:
    from secrets import token_urlsafe

    col = await _owned(session, user_id, collection_id)
    if col.public_share_token is None:
        col.public_share_token = token_urlsafe(24)
        await session.commit()
    return col.public_share_token


async def regenerate_public_share(session: AsyncSession, user_id: UUID, collection_id: UUID) -> str:
    from secrets import token_urlsafe

    col = await _owned(session, user_id, collection_id)
    col.public_share_token = token_urlsafe(24)
    await session.commit()
    return col.public_share_token


async def disable_public_share(session: AsyncSession, user_id: UUID, collection_id: UUID) -> None:
    col = await _owned(session, user_id, collection_id)
    if col.public_share_token is not None:
        col.public_share_token = None
        await session.commit()
