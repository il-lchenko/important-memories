from datetime import datetime, timezone

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.core.errors import ConflictError, PermissionDeniedError
from app.domain.models import Event, EventSettings, EventStatus, Plan, User
from app.domain.schemas.entitlements import EntitlementFeaturesOut, EntitlementsOut


def has_payment_bypass(user: User) -> bool:
    return user.is_admin


def _month_start(now: datetime | None = None) -> datetime:
    now = now or datetime.now(timezone.utc)
    return now.replace(day=1, hour=0, minute=0, second=0, microsecond=0)


async def count_free_events_this_month(session: AsyncSession, user_id) -> int:
    stmt = (
        select(func.count(Event.id))
        .join(EventSettings, EventSettings.event_id == Event.id)
        .where(
            Event.user_id == user_id,
            EventSettings.plan == Plan.FREE,
            Event.status.in_((EventStatus.ACTIVE, EventStatus.COMPLETED)),
            Event.created_at >= _month_start(),
        )
    )
    return int((await session.execute(stmt)).scalar_one())


async def get_entitlements(session: AsyncSession, user: User) -> EntitlementsOut:
    limit = settings.FREE_EVENTS_PER_MONTH
    used = await count_free_events_this_month(session, user.id)
    left = None if limit is None or user.is_admin else max(0, limit - used)
    return EntitlementsOut(
        tier="admin" if user.is_admin else "free",
        is_admin=user.is_admin,
        subscription_enabled=settings.SUBSCRIPTION_ENABLED,
        free_events_per_month=limit,
        free_events_used=used,
        free_events_left=left,
        features=EntitlementFeaturesOut(solo_album=False, mini_albums=False),
    )


async def ensure_can_activate(session: AsyncSession, user: User | None, event: Event) -> None:
    """Бесплатная активация черновика. Платные тарифы включает только оплата."""
    if user is not None and has_payment_bypass(user):
        return
    if event.settings.plan != Plan.FREE:
        raise PermissionDeniedError(
            "Платный тариф активируется после оплаты",
            details={"plan": event.settings.plan.value},
        )
    limit = settings.FREE_EVENTS_PER_MONTH
    if limit is None or user is None:
        return
    used = await count_free_events_this_month(session, user.id)
    if used >= limit:
        raise ConflictError(
            "Бесплатные события в этом месяце закончились",
            details={"reason": "free_events_limit", "limit": limit, "used": used},
        )
