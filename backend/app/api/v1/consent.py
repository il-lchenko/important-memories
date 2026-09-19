"""Endpoints для принятия юр. документов пользователями.

Соответствие ст. 9 152-ФЗ (в редакции с 01.09.2025): отдельное согласие
на обработку ПД оформляется отдельно от иных документов; оператор должен
уметь доказать факт получения согласия — что и обеспечивает эта таблица.
"""
from typing import Annotated

from fastapi import APIRouter, Header, Request

from app.api.deps import CurrentUserId, SessionDep
from app.core.client_ctx import client_ip, hash_fingerprint, hash_ip
from app.domain.schemas.consent import (
    ConsentAcceptIn,
    ConsentOut,
    GuestConsentAcceptIn,
)
from app.repos import consent_repo

router = APIRouter()


# Актуальная версия юр. документов. Меняется при существенных правках.
CURRENT_DOC_VERSION = "2.0"
ALL_DOC_TYPES = ("offer", "privacy", "consent", "content_rules")


@router.get("/consent/status")
async def consent_status_user(
    user_id: CurrentUserId,
    session: SessionDep,
) -> dict:
    """Возвращает список типов документов текущей версии, которые Хост ещё
    не принял. Клиент, обнаружив непустой список, показывает ConsentScreen."""
    missing = []
    for doc_type in ALL_DOC_TYPES:
        if not await consent_repo.has_user_accepted(
            session, user_id, doc_type, CURRENT_DOC_VERSION
        ):
            missing.append(doc_type)
    return {
        "current_version": CURRENT_DOC_VERSION,
        "missing": missing,
        "needs_accept": bool(missing),
    }


@router.post("/consent", response_model=ConsentOut, status_code=201)
async def accept_consent_user(
    payload: ConsentAcceptIn,
    user_id: CurrentUserId,
    request: Request,
    session: SessionDep,
    user_agent: Annotated[str | None, Header(alias="User-Agent")] = None,
) -> ConsentOut:
    """Хост принимает документ (offer / privacy / consent / content_rules).
    Требуется bearer-токен, чтобы связать запись с user_id."""
    ip = client_ip(request)
    row = await consent_repo.record(
        session,
        doc_type=payload.doc_type,
        doc_version=payload.doc_version,
        user_id=user_id,
        ip_hash=hash_ip(ip),
        user_agent=user_agent,
    )
    await session.commit()
    return ConsentOut(
        id=row.id,
        doc_type=payload.doc_type,
        doc_version=row.doc_version,
        accepted_at=row.accepted_at,
    )


@router.post("/guest/consent", response_model=ConsentOut, status_code=201)
async def accept_consent_guest(
    payload: GuestConsentAcceptIn,
    request: Request,
    session: SessionDep,
    user_agent: Annotated[str | None, Header(alias="User-Agent")] = None,
) -> ConsentOut:
    """Гость принимает документ ДО создания Guest-записи. Передаёт
    fingerprint устройства — по нему потом свяжется с guest_id при join.
    """
    ip = client_ip(request)
    fp_hash = hash_fingerprint(payload.fingerprint)
    row = await consent_repo.record(
        session,
        doc_type=payload.doc_type,
        doc_version=payload.doc_version,
        fingerprint_hash=fp_hash,
        ip_hash=hash_ip(ip),
        user_agent=user_agent,
    )
    await session.commit()
    return ConsentOut(
        id=row.id,
        doc_type=payload.doc_type,
        doc_version=row.doc_version,
        accepted_at=row.accepted_at,
    )
