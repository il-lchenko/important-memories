"""Repo для JoinAttempt — аудит попыток входа в альбом."""
from datetime import datetime, timedelta, timezone
from uuid import UUID

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.domain.models import JoinAttempt, JoinAttemptOutcome


async def record(
    session: AsyncSession,
    *,
    event_id: UUID | None,
    ip_hash: str | None,
    fingerprint_hash: str | None,
    short_code_tried: str,
    pin_tried: bool,
    outcome: JoinAttemptOutcome,
) -> None:
    """Insert одной записи. Не бросает наружу — если запись не удалась, оставляем
    приложение работать (аудит не должен ломать основной flow)."""
    row = JoinAttempt(
        event_id=event_id,
        ip_hash=ip_hash,
        fingerprint_hash=fingerprint_hash,
        # Обрезаем на всякий случай — колонка String(16).
        short_code_tried=(short_code_tried or "")[:16],
        pin_tried=pin_tried,
        outcome=outcome,
    )
    session.add(row)
    await session.commit()


async def has_ok_for_event_and_fingerprint(
    session: AsyncSession, event_id: UUID, fingerprint_hash: str, hours: int = 24
) -> bool:
    """Есть ли успешная (outcome=OK) попытка этого fingerprint для этого события
    за окно. Используется для решения «это re-join уже знакомого альбома → лимит
    не применять» vs «новый альбом → считаем в квоту»."""
    since = datetime.now(timezone.utc) - timedelta(hours=hours)
    stmt = (
        select(func.count())
        .select_from(JoinAttempt)
        .where(JoinAttempt.event_id == event_id)
        .where(JoinAttempt.fingerprint_hash == fingerprint_hash)
        .where(JoinAttempt.outcome == JoinAttemptOutcome.OK)
        .where(JoinAttempt.created_at >= since)
    )
    return int((await session.execute(stmt)).scalar() or 0) > 0


async def count_new_events_for_fingerprint(
    session: AsyncSession, fingerprint_hash: str, hours: int = 24
) -> int:
    """Сколько РАЗНЫХ event_id этот fingerprint успешно присоединил за окно.
    Учитываются только outcome=OK. Считаются distinct-event, чтобы повторный
    вход в уже присоединённый альбом не считался «новым»."""
    since = datetime.now(timezone.utc) - timedelta(hours=hours)
    stmt = (
        select(func.count(func.distinct(JoinAttempt.event_id)))
        .where(JoinAttempt.fingerprint_hash == fingerprint_hash)
        .where(JoinAttempt.outcome == JoinAttemptOutcome.OK)
        .where(JoinAttempt.event_id.is_not(None))
        .where(JoinAttempt.created_at >= since)
    )
    result = await session.execute(stmt)
    return int(result.scalar() or 0)


async def stats_for_event(
    session: AsyncSession, event_id: UUID, hours: int = 24
) -> dict:
    """Агрегация попыток для конкретного события за окно.
    Возвращает dict {outcome_value: count} + unique_ips, unique_fingerprints."""
    since = datetime.now(timezone.utc) - timedelta(hours=hours)
    base = select(JoinAttempt).where(
        JoinAttempt.event_id == event_id,
        JoinAttempt.created_at >= since,
    )
    # by-outcome
    per_outcome_stmt = (
        select(JoinAttempt.outcome, func.count())
        .where(JoinAttempt.event_id == event_id, JoinAttempt.created_at >= since)
        .group_by(JoinAttempt.outcome)
    )
    per_outcome = {row[0].value: int(row[1]) for row in (await session.execute(per_outcome_stmt)).all()}

    # unique ip / fp
    uniq_ip_stmt = select(func.count(func.distinct(JoinAttempt.ip_hash))).where(
        JoinAttempt.event_id == event_id,
        JoinAttempt.created_at >= since,
        JoinAttempt.ip_hash.is_not(None),
    )
    uniq_fp_stmt = select(func.count(func.distinct(JoinAttempt.fingerprint_hash))).where(
        JoinAttempt.event_id == event_id,
        JoinAttempt.created_at >= since,
        JoinAttempt.fingerprint_hash.is_not(None),
    )
    uniq_ip = int((await session.execute(uniq_ip_stmt)).scalar() or 0)
    uniq_fp = int((await session.execute(uniq_fp_stmt)).scalar() or 0)
    total = int((await session.execute(select(func.count()).select_from(base.subquery()))).scalar() or 0)
    return {
        "total": total,
        "per_outcome": per_outcome,
        "unique_ips": uniq_ip,
        "unique_fingerprints": uniq_fp,
    }
