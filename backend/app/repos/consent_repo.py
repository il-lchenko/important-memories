"""Работа с consent_records — аудит принятия юр. документов."""
from uuid import UUID

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.domain.models.models import ConsentRecord


async def record(
    session: AsyncSession,
    *,
    doc_type: str,
    doc_version: str,
    user_id: UUID | None = None,
    guest_id: UUID | None = None,
    fingerprint_hash: str | None = None,
    ip_hash: str | None = None,
    user_agent: str | None = None,
) -> ConsentRecord:
    """Записывает факт принятия документа. Не проверяет дубликаты —
    повторное принятие той же версии создаёт новую запись."""
    row = ConsentRecord(
        user_id=user_id,
        guest_id=guest_id,
        fingerprint_hash=fingerprint_hash,
        doc_type=doc_type,
        doc_version=doc_version,
        ip_hash=ip_hash,
        user_agent=(user_agent[:200] if user_agent else None),
    )
    session.add(row)
    await session.flush()
    return row


async def has_user_accepted(
    session: AsyncSession,
    user_id: UUID,
    doc_type: str,
    doc_version: str,
) -> bool:
    stmt = (
        select(ConsentRecord.id)
        .where(
            ConsentRecord.user_id == user_id,
            ConsentRecord.doc_type == doc_type,
            ConsentRecord.doc_version == doc_version,
        )
        .limit(1)
    )
    return (await session.execute(stmt)).scalar_one_or_none() is not None


async def has_fingerprint_accepted(
    session: AsyncSession,
    fingerprint_hash: str,
    doc_type: str,
    doc_version: str,
) -> bool:
    stmt = (
        select(ConsentRecord.id)
        .where(
            ConsentRecord.fingerprint_hash == fingerprint_hash,
            ConsentRecord.doc_type == doc_type,
            ConsentRecord.doc_version == doc_version,
        )
        .limit(1)
    )
    return (await session.execute(stmt)).scalar_one_or_none() is not None


async def link_fingerprint_to_guest(
    session: AsyncSession,
    fingerprint_hash: str,
    guest_id: UUID,
) -> int:
    """При создании Guest-сессии проставляем guest_id тем consent-записям,
    которые были сделаны с этим fingerprint до появления Guest-записи."""
    from sqlalchemy import update

    stmt = (
        update(ConsentRecord)
        .where(
            ConsentRecord.fingerprint_hash == fingerprint_hash,
            ConsentRecord.guest_id.is_(None),
        )
        .values(guest_id=guest_id)
    )
    result = await session.execute(stmt)
    return result.rowcount or 0
