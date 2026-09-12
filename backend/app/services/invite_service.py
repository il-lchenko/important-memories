"""Сервис для персональных приглашений.

Хост создаёт invite для конкретного гостя («для Анны») → получает ссылку
`impomento.pro/i/<token>`. Гость по ней получает сессию БЕЗ PIN и обходит
лимит «3 новых альбома / 24ч».

Токен одноразовый: после первого использования invite.used_at = now(),
повторный переход по той же ссылке → 410 (можно смотреть, но не создать
вторую сессию тем же токеном).
"""
from datetime import datetime, timedelta, timezone
from secrets import token_urlsafe
from uuid import UUID

from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.core.errors import ConflictError, NotFoundError, PermissionDeniedError
from app.domain.models import InviteToken
from app.domain.schemas.guests import (
    GuestSessionOut,
    InviteCreateIn,
    InviteTokenOut,
)
from app.repos import event_repo, invite_repo
from app.services import guest_service


def _build_invite_url(token: str) -> str:
    base = settings.PUBLIC_PWA_BASE_URL.rstrip("/")
    return f"{base}/i/{token}"


def _to_out(invite: InviteToken) -> InviteTokenOut:
    return InviteTokenOut(
        id=invite.id,
        token=invite.token,
        display_name=invite.display_name,
        created_at=invite.created_at,
        used_at=invite.used_at,
        expires_at=invite.expires_at,
        invite_url=_build_invite_url(invite.token),
    )


async def create_invite(
    session: AsyncSession,
    *,
    actor_user_id: UUID,
    event_id: UUID,
    payload: InviteCreateIn,
) -> InviteTokenOut:
    event = await event_repo.get_by_id(session, event_id)
    if event is None:
        raise NotFoundError("Event not found")
    if event.user_id != actor_user_id:
        raise PermissionDeniedError("Только владелец события создаёт приглашения")
    # Инвайт нужен гостю для СОЗДАНИЯ сессии → нужен ACTIVE event (в completed
    # нельзя снимать; для чтения альбома есть public_share_token). Блокируем
    # создание сразу, чтобы избежать «одноразовая ссылка, которая никогда
    # не сработала».
    from app.domain.models import EventStatus
    if event.status != EventStatus.ACTIVE:
        raise ConflictError(
            "Приглашения можно создавать только для активного события",
            details={"status": event.status.value},
        )

    expires_at = None
    if payload.ttl_days is not None:
        expires_at = datetime.now(timezone.utc) + timedelta(days=payload.ttl_days)

    invite = InviteToken(
        event_id=event.id,
        token=token_urlsafe(24),  # ~32 chars ≈ 192 bits
        display_name=payload.display_name,
        expires_at=expires_at,
    )
    await invite_repo.create(session, invite)
    await session.commit()
    return _to_out(invite)


async def list_invites(
    session: AsyncSession, *, actor_user_id: UUID, event_id: UUID
) -> list[InviteTokenOut]:
    event = await event_repo.get_by_id(session, event_id)
    if event is None:
        raise NotFoundError("Event not found")
    if event.user_id != actor_user_id:
        raise PermissionDeniedError("Только владелец видит приглашения")
    rows = await invite_repo.list_for_event(session, event.id)
    return [_to_out(r) for r in rows]


async def delete_invite(
    session: AsyncSession,
    *,
    actor_user_id: UUID,
    event_id: UUID,
    invite_id: UUID,
) -> None:
    event = await event_repo.get_by_id(session, event_id)
    if event is None:
        raise NotFoundError("Event not found")
    if event.user_id != actor_user_id:
        raise PermissionDeniedError("Только владелец удаляет приглашения")
    await invite_repo.delete_by_id(session, invite_id)


async def preview_invite(session: AsyncSession, token: str) -> dict:
    """Гостевой preview — что за событие, кто пригласил, использован ли токен,
    закрыто ли событие. Клиент показывает разные экраны для каждой ситуации."""
    from app.domain.models import EventStatus

    row = await invite_repo.get_by_token_with_event(session, token)
    if row is None:
        raise NotFoundError("Приглашение не найдено")
    invite, event = row
    used = invite.used_at is not None
    expired = (
        invite.expires_at is not None
        and invite.expires_at <= datetime.now(timezone.utc)
    )
    event_closed = event.status != EventStatus.ACTIVE
    return {
        "display_name": invite.display_name,
        "event_title": event.title,
        "event_short_code": event.short_code,
        "event_status": event.status.value,
        "public_share_token": event.public_share_token,
        "used": used,
        "expired": expired,
        "event_closed": event_closed,
    }


async def join_by_invite(
    session: AsyncSession,
    *,
    token: str,
    name: str | None,
    fingerprint: str,
    actor_user_id: UUID | None,
    client_ip: str | None,
) -> GuestSessionOut:
    """Использовать invite: создаёт guest-сессию в обход PIN и лимита альбомов.
    Токен помечается использованным."""
    row = await invite_repo.get_by_token_with_event(session, token)
    if row is None:
        raise NotFoundError("Приглашение не найдено")
    invite, event = row

    if invite.expires_at is not None and invite.expires_at <= datetime.now(timezone.utc):
        raise ConflictError("Приглашение истекло")
    if invite.used_at is not None:
        raise ConflictError("Приглашение уже использовано")

    # Если имя не передано — берём из display_name инвайта.
    effective_name = (name or "").strip() or invite.display_name

    result = await guest_service.join(
        session,
        short_code=event.short_code,
        name=effective_name,
        fingerprint=fingerprint,
        actor_user_id=actor_user_id,
        client_ip=client_ip,
        pin=None,
        invite_bypass=True,
    )

    # Пометить invite как использованный.
    await invite_repo.mark_used(session, invite, result.guest_id)
    return result
