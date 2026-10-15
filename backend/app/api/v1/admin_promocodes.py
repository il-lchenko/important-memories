from datetime import datetime, timezone
from uuid import UUID

from fastapi import APIRouter, Query

from app.api.deps import AdminUser, SessionDep
from app.core.errors import ConflictError, NotFoundError
from app.domain.models import Promocode, PromocodeKind
from app.domain.schemas.promocodes import (
    AdminToggleOut,
    PromocodeCreateIn,
    PromocodeOut,
    PromocodePatchIn,
    PromocodeRedemptionOut,
)
from app.repos import promocode_repo, user_repo

router = APIRouter()


@router.post("/promocodes", response_model=PromocodeOut)
async def admin_create_promocode(
    payload: PromocodeCreateIn,
    admin: AdminUser,
    session: SessionDep,
) -> PromocodeOut:
    code = payload.code.strip().upper()
    if await promocode_repo.get_by_code(session, code) is not None:
        raise ConflictError("Промокод с таким кодом уже существует")

    owner_id: UUID | None = None
    if payload.owner_user_email:
        owner = await user_repo.get_by_email(session, payload.owner_user_email.strip().lower())
        if owner is None:
            raise NotFoundError("Пользователь с таким email не найден")
        owner_id = owner.id

    promo = Promocode(
        code=code,
        kind=payload.kind,
        discount_type=payload.discount_type,
        discount_value=payload.discount_value,
        max_redemptions=payload.max_redemptions,
        redemptions_count=0,
        expires_at=payload.expires_at,
        applies_to=payload.applies_to,
        min_amount_kopecks=payload.min_amount_kopecks,
        single_use_per_user=payload.single_use_per_user,
        created_by_user_id=admin.id,
        owner_user_id=owner_id,
    )
    await promocode_repo.create(session, promo)
    await session.commit()
    return PromocodeOut.model_validate(promo)


@router.get("/promocodes", response_model=list[PromocodeOut])
async def admin_list_promocodes(
    admin: AdminUser,
    session: SessionDep,
    kind: PromocodeKind | None = Query(default=None),
) -> list[PromocodeOut]:
    promos = await promocode_repo.list_all(session, kind=kind)
    return [PromocodeOut.model_validate(p) for p in promos]


@router.patch("/promocodes/{promocode_id}", response_model=PromocodeOut)
async def admin_patch_promocode(
    promocode_id: UUID,
    payload: PromocodePatchIn,
    admin: AdminUser,
    session: SessionDep,
) -> PromocodeOut:
    promo = await promocode_repo.get_by_id(session, promocode_id)
    if promo is None:
        raise NotFoundError("Промокод не найден")
    if payload.max_redemptions is not None:
        promo.max_redemptions = payload.max_redemptions
    if payload.expires_at is not None:
        promo.expires_at = payload.expires_at
    if payload.discount_value is not None:
        promo.discount_value = payload.discount_value
    await session.commit()
    return PromocodeOut.model_validate(promo)


@router.delete("/promocodes/{promocode_id}", status_code=204)
async def admin_delete_promocode(
    promocode_id: UUID,
    admin: AdminUser,
    session: SessionDep,
) -> None:
    """Soft-delete через expires_at=now — существующие redemptions сохраняются
    для истории, но новые применения блокируются validate_promocode."""
    promo = await promocode_repo.get_by_id(session, promocode_id)
    if promo is None:
        raise NotFoundError("Промокод не найден")
    promo.expires_at = datetime.now(timezone.utc)
    await session.commit()


@router.get("/promocodes/{promocode_id}/redemptions", response_model=list[PromocodeRedemptionOut])
async def admin_list_redemptions(
    promocode_id: UUID,
    admin: AdminUser,
    session: SessionDep,
) -> list[PromocodeRedemptionOut]:
    promo = await promocode_repo.get_by_id(session, promocode_id)
    if promo is None:
        raise NotFoundError("Промокод не найден")
    redemptions = await promocode_repo.list_redemptions(session, promocode_id)
    return [PromocodeRedemptionOut.model_validate(r) for r in redemptions]


@router.post("/users/{target_user_id}/toggle_admin", response_model=AdminToggleOut)
async def admin_toggle_admin(
    target_user_id: UUID,
    admin: AdminUser,
    session: SessionDep,
) -> AdminToggleOut:
    """Переключает флаг is_admin у другого юзера. Только для root-админа (Ильи)."""
    target = await user_repo.get_by_id(session, target_user_id)
    if target is None:
        raise NotFoundError("Пользователь не найден")
    if target.id == admin.id:
        raise ConflictError("Нельзя изменить свой собственный флаг is_admin")
    target.is_admin = not target.is_admin
    await session.commit()
    return AdminToggleOut(user_id=target.id, is_admin=target.is_admin)
