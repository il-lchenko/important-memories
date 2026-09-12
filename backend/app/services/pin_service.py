"""Сервис для управления PIN события (хост-only) и статистикой попыток входа."""
from secrets import randbelow
from uuid import UUID

from sqlalchemy.ext.asyncio import AsyncSession

from app.core.errors import ConflictError, PermissionDeniedError
from app.domain.models import EventStatus, JoinAttemptOutcome
from app.domain.schemas.guests import EventPinOut, JoinStatsOut
from app.repos import event_repo, join_attempt_repo


def _generate_pin() -> str:
    """4-digit numeric PIN. secrets.randbelow — CSPRNG."""
    return f"{randbelow(10000):04d}"


async def set_pin(
    session: AsyncSession,
    *,
    actor_user_id: UUID,
    event_id: UUID,
    enabled: bool,
    pin: str | None,
) -> EventPinOut:
    """Три сценария:
    - enabled=True, pin="1234" — установить конкретный PIN
    - enabled=True, pin=None   — сгенерировать случайный
    - enabled=False            — выключить, PIN очищается
    Только владелец события.
    """
    event = await event_repo.get_by_id(session, event_id)
    if event is None:
        raise ConflictError("Event not found")
    if event.user_id != actor_user_id:
        raise PermissionDeniedError("Только владелец события может менять PIN")

    if enabled:
        event.entry_pin = pin or _generate_pin()
        event.pin_enabled = True
    else:
        event.entry_pin = None
        event.pin_enabled = False
    await session.commit()
    return EventPinOut(pin_enabled=event.pin_enabled, entry_pin=event.entry_pin)


async def get_pin(
    session: AsyncSession, *, actor_user_id: UUID, event_id: UUID
) -> EventPinOut:
    event = await event_repo.get_by_id(session, event_id)
    if event is None:
        raise ConflictError("Event not found")
    if event.user_id != actor_user_id:
        raise PermissionDeniedError("Только владелец события видит PIN")
    return EventPinOut(pin_enabled=event.pin_enabled, entry_pin=event.entry_pin)


# Стата попыток входа для хоста
_SUSPICIOUS_THRESHOLD_1H = 20  # >20 bad_pin+bad_code за час → флаг suspicious


async def get_join_stats(
    session: AsyncSession, *, actor_user_id: UUID, event_id: UUID, hours: int = 24
) -> JoinStatsOut:
    event = await event_repo.get_by_id(session, event_id)
    if event is None:
        raise ConflictError("Event not found")
    if event.user_id != actor_user_id:
        raise PermissionDeniedError("Только владелец видит статистику")

    # Для окна 24ч
    agg24 = await join_attempt_repo.stats_for_event(session, event_id, hours=hours)
    # Для окна 1ч — определить всплеск
    agg1 = await join_attempt_repo.stats_for_event(session, event_id, hours=1)
    per1 = agg1.get("per_outcome", {})
    suspicious = (
        int(per1.get(JoinAttemptOutcome.BAD_CODE.value, 0))
        + int(per1.get(JoinAttemptOutcome.BAD_PIN.value, 0))
    ) >= _SUSPICIOUS_THRESHOLD_1H

    per = agg24.get("per_outcome", {})
    known_keys = {"ok", "bad_code", "bad_pin", "pin_required", "rate_limited"}
    other = sum(int(v) for k, v in per.items() if k not in known_keys)
    return JoinStatsOut(
        window_hours=hours,
        total=int(agg24.get("total", 0)),
        ok=int(per.get(JoinAttemptOutcome.OK.value, 0)),
        bad_code=int(per.get(JoinAttemptOutcome.BAD_CODE.value, 0)),
        bad_pin=int(per.get(JoinAttemptOutcome.BAD_PIN.value, 0)),
        pin_required=int(per.get(JoinAttemptOutcome.PIN_REQUIRED.value, 0)),
        rate_limited=int(per.get(JoinAttemptOutcome.RATE_LIMITED.value, 0)),
        other=other,
        unique_ips=int(agg24.get("unique_ips", 0)),
        unique_fingerprints=int(agg24.get("unique_fingerprints", 0)),
        suspicious=suspicious,
    )


# Утилита для frontends: возвращает status enum значение, если событие уже сработало.
def event_is_over(status: EventStatus) -> bool:
    return status in (EventStatus.COMPLETED, EventStatus.CANCELLED)
