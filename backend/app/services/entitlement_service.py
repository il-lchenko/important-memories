from datetime import datetime, timezone

from sqlalchemy import func, or_, select
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


def _free_events_stmt(user_id):
    return (
        select(func.count(Event.id))
        .join(EventSettings, EventSettings.event_id == Event.id)
        .where(Event.user_id == user_id, EventSettings.plan == Plan.FREE)
    )


async def count_free_events_this_month(session: AsyncSession, user_id) -> int:
    """Бесплатные активации в этом календарном месяце, включая уже удалённые альбомы."""
    stmt = _free_events_stmt(user_id).where(Event.activated_at >= _month_start())
    return int((await session.execute(stmt)).scalar_one())


async def count_active_free_events(session: AsyncSession, user_id) -> int:
    """Бесплатные альбомы, которые сейчас живут: идут или завершены, срок хранения не истёк."""
    now = datetime.now(timezone.utc)
    stmt = _free_events_stmt(user_id).where(
        Event.status.in_((EventStatus.ACTIVE, EventStatus.COMPLETED)),
        or_(Event.expires_at.is_(None), Event.expires_at > now),
    )
    return int((await session.execute(stmt)).scalar_one())


def _free_limits() -> tuple[int | None, int | None]:
    """(одновременно, в месяц). Лимиты вступают в силу вместе с офертой 2.4 (PRICING_V2_FROM)."""
    if datetime.now(timezone.utc) < datetime.fromisoformat(settings.PRICING_V2_FROM):
        return None, None
    return settings.FREE_ACTIVE_EVENTS, settings.FREE_EVENTS_PER_MONTH


def _left(limit: int | None, used: int, is_admin: bool) -> int | None:
    if limit is None or is_admin:
        return None
    return max(0, limit - used)


async def get_entitlements(session: AsyncSession, user: User) -> EntitlementsOut:
    active_limit, monthly_limit = _free_limits()
    used = await count_free_events_this_month(session, user.id)
    active = await count_active_free_events(session, user.id)
    return EntitlementsOut(
        tier="admin" if user.is_admin else "free",
        is_admin=user.is_admin,
        subscription_enabled=settings.SUBSCRIPTION_ENABLED,
        free_events_per_month=monthly_limit,
        free_events_used=used,
        free_events_left=_left(monthly_limit, used, user.is_admin),
        free_active_limit=active_limit,
        free_active_used=active,
        free_active_left=_left(active_limit, active, user.is_admin),
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
    if user is None:
        return
    active_limit, monthly_limit = _free_limits()
    if active_limit is not None:
        active = await count_active_free_events(session, user.id)
        if active >= active_limit:
            raise ConflictError(
                f"Одновременно можно вести {active_limit} бесплатных альбома. "
                "Удалите ненужный или выберите платный тариф.",
                details={"reason": "free_active_limit", "limit": active_limit, "used": active},
            )
    if monthly_limit is not None:
        used = await count_free_events_this_month(session, user.id)
        if used >= monthly_limit:
            raise ConflictError(
                f"В этом месяце уже создано {used} бесплатных альбомов — это максимум. "
                "Новые бесплатные откроются с 1-го числа, или выберите платный тариф.",
                details={"reason": "free_events_limit", "limit": monthly_limit, "used": used},
            )
