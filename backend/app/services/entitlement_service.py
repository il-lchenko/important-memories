from dataclasses import dataclass
from datetime import datetime, timezone

from sqlalchemy import func, or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.core.errors import ConflictError, PermissionDeniedError
from app.domain.models import (
    Event,
    EventKind,
    EventSettings,
    EventStatus,
    Frame,
    FrameStatus,
    Plan,
    Subscription,
    SubscriptionStatus,
    User,
)
from app.domain.schemas.entitlements import EntitlementFeaturesOut, EntitlementsOut


def has_payment_bypass(user: User) -> bool:
    return user.is_admin


def _month_start(now: datetime | None = None) -> datetime:
    now = now or datetime.now(timezone.utc)
    return now.replace(day=1, hour=0, minute=0, second=0, microsecond=0)


async def has_plus(session: AsyncSession, user: User) -> bool:
    """Подписка «Плюс» действует: админ, либо оплаченный период ещё не закончился.
    Пока SUBSCRIPTION_ENABLED выключен, подписок нет и действуют бесплатные лимиты."""
    if user.is_admin:
        return True
    if not settings.SUBSCRIPTION_ENABLED:
        return False
    now = datetime.now(timezone.utc)
    stmt = select(Subscription.id).where(
        Subscription.user_id == user.id,
        Subscription.status.in_((SubscriptionStatus.ACTIVE.value, SubscriptionStatus.PAST_DUE.value)),
        Subscription.current_period_end > now,
    )
    return (await session.execute(stmt)).first() is not None


# ── Бесплатные события (≤5 гостей) ────────────────────────────────────────────

def _free_events_stmt(user_id):
    return (
        select(func.count(Event.id))
        .join(EventSettings, EventSettings.event_id == Event.id)
        .where(
            Event.user_id == user_id,
            Event.kind == EventKind.EVENT.value,
            EventSettings.plan == Plan.FREE,
        )
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


def _free_limits(plus: bool = False) -> tuple[int | None, int | None]:
    """(одновременно, в месяц). Лимиты вступают в силу вместе с офертой 2.4 (PRICING_V2_FROM)."""
    if datetime.now(timezone.utc) < datetime.fromisoformat(settings.PRICING_V2_FROM):
        return None, None
    if plus:
        return settings.PLUS_FREE_ACTIVE_EVENTS, settings.PLUS_FREE_EVENTS_PER_MONTH
    return settings.FREE_ACTIVE_EVENTS, settings.FREE_EVENTS_PER_MONTH


def _left(limit: int | None, used: int, is_admin: bool) -> int | None:
    if limit is None or is_admin:
        return None
    return max(0, limit - used)


# ── Соло-альбомы ──────────────────────────────────────────────────────────────

@dataclass(frozen=True)
class SoloLimits:
    frames_per_month: int
    stored_frames: int
    retention_days: int
    plus: bool


async def solo_limits(session: AsyncSession, user: User) -> SoloLimits:
    plus = await has_plus(session, user)
    if plus:
        return SoloLimits(
            settings.SOLO_PLUS_FRAMES_PER_MONTH,
            settings.SOLO_PLUS_STORED_FRAMES,
            settings.SOLO_PLUS_RETENTION_DAYS,
            True,
        )
    return SoloLimits(
        settings.SOLO_FREE_FRAMES_PER_MONTH,
        settings.SOLO_FREE_STORED_FRAMES,
        settings.SOLO_FREE_RETENTION_DAYS,
        False,
    )


def _solo_frames_stmt(user_id):
    return (
        select(func.count(Frame.id))
        .join(Event, Event.id == Frame.event_id)
        .where(
            Event.user_id == user_id,
            Event.kind == EventKind.SOLO.value,
            Frame.status.in_((FrameStatus.UPLOADED, FrameStatus.PENDING)),
        )
    )


async def solo_usage(session: AsyncSession, user_id) -> tuple[int, int]:
    """(кадров снято в этом месяце, кадров хранится сейчас) по всем соло-альбомам пользователя."""
    month = (await session.execute(_solo_frames_stmt(user_id).where(Frame.captured_at >= _month_start()))).scalar_one()
    stored = (
        await session.execute(_solo_frames_stmt(user_id).where(Event.storage_purged_at.is_(None)))
    ).scalar_one()
    return int(month), int(stored)


async def solo_frames_left(session: AsyncSession, user: User) -> int:
    """Сколько кадров можно снять в соло прямо сейчас: минимум из месячной квоты и места в хранилище."""
    limits = await solo_limits(session, user)
    month, stored = await solo_usage(session, user.id)
    return max(0, min(limits.frames_per_month - month, limits.stored_frames - stored))


async def ensure_can_shoot_solo(session: AsyncSession, user: User) -> None:
    limits = await solo_limits(session, user)
    month, stored = await solo_usage(session, user.id)
    if month >= limits.frames_per_month:
        raise ConflictError(
            f"В этом месяце вы уже сняли {month} кадров в соло-альбомах: это максимум. "
            "Новые откроются с 1-го числа или с подпиской «Плюс».",
            details={"reason": "solo_month_limit", "limit": limits.frames_per_month, "used": month, "plus": limits.plus},
        )
    if stored >= limits.stored_frames:
        raise ConflictError(
            f"В соло-альбомах уже хранится {stored} кадров: это максимум. "
            "Удалите ненужные кадры или оформите «Плюс».",
            details={"reason": "solo_storage_limit", "limit": limits.stored_frames, "used": stored, "plus": limits.plus},
        )


# ── Мини-альбомы ──────────────────────────────────────────────────────────────

@dataclass(frozen=True)
class MiniLimits:
    albums: int | None
    frames_per_album: int
    plus: bool


async def mini_limits(session: AsyncSession, user: User) -> MiniLimits:
    plus = await has_plus(session, user)
    if plus:
        return MiniLimits(None, settings.MINI_PLUS_FRAMES_PER_ALBUM, True)
    return MiniLimits(settings.MINI_FREE_ALBUMS, settings.MINI_FREE_FRAMES_PER_ALBUM, False)


# ── Права на оформление ───────────────────────────────────────────────────────

FREE_QR_STYLES = frozenset({"classic"})
FREE_TITLE_FONTS = frozenset({"playfair"})


async def ensure_can_style(
    session: AsyncSession, user: User | None, *, qr_style: str | None, title_font: str | None,
    current_qr: str | None, current_font: str | None,
) -> None:
    """Дополнительные QR-стили и шрифты названия доступны с «Плюс». Уже выбранное
    раньше значение остаётся доступным (события не теряют оформление)."""
    wants_paid = (
        (qr_style is not None and qr_style not in FREE_QR_STYLES and qr_style != current_qr)
        or (title_font is not None and title_font not in FREE_TITLE_FONTS and title_font != current_font)
    )
    if not wants_paid or user is None:
        return
    if not settings.SUBSCRIPTION_ENABLED:
        return
    if not await has_plus(session, user):
        raise PermissionDeniedError(
            "Дополнительное оформление доступно с подпиской «Плюс»",
            details={"reason": "plus_required"},
        )


async def get_entitlements(session: AsyncSession, user: User) -> EntitlementsOut:
    plus = await has_plus(session, user)
    active_limit, monthly_limit = _free_limits(plus)
    used = await count_free_events_this_month(session, user.id)
    active = await count_active_free_events(session, user.id)
    solo = await solo_limits(session, user)
    solo_month, solo_stored = await solo_usage(session, user.id)
    mini = await mini_limits(session, user)
    return EntitlementsOut(
        tier="admin" if user.is_admin else ("subscription" if plus else "free"),
        is_admin=user.is_admin,
        subscription_enabled=settings.SUBSCRIPTION_ENABLED,
        plus=plus,
        free_events_per_month=monthly_limit,
        free_events_used=used,
        free_events_left=_left(monthly_limit, used, user.is_admin),
        free_active_limit=active_limit,
        free_active_used=active,
        free_active_left=_left(active_limit, active, user.is_admin),
        solo_frames_per_month=solo.frames_per_month,
        solo_frames_used=solo_month,
        solo_frames_left=max(0, min(solo.frames_per_month - solo_month, solo.stored_frames - solo_stored)),
        solo_stored_limit=solo.stored_frames,
        solo_stored_used=solo_stored,
        solo_retention_days=solo.retention_days,
        mini_albums_limit=mini.albums,
        mini_frames_per_album=mini.frames_per_album,
        features=EntitlementFeaturesOut(
            solo_album=True,
            mini_albums=True,
            extra_styles=plus or not settings.SUBSCRIPTION_ENABLED,
        ),
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
    plus = await has_plus(session, user)
    active_limit, monthly_limit = _free_limits(plus)
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
