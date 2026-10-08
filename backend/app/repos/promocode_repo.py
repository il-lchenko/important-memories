from uuid import UUID

from sqlalchemy import func, or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.domain.models import Promocode, PromocodeKind, PromocodeRedemption


async def get_by_id(session: AsyncSession, promocode_id: UUID) -> Promocode | None:
    return await session.get(Promocode, promocode_id)


async def get_by_code(session: AsyncSession, code: str) -> Promocode | None:
    stmt = select(Promocode).where(Promocode.code == code.strip().upper())
    return (await session.execute(stmt)).scalar_one_or_none()


async def get_by_code_for_update(session: AsyncSession, code: str) -> Promocode | None:
    stmt = (
        select(Promocode)
        .where(Promocode.code == code.strip().upper())
        .with_for_update()
    )
    return (await session.execute(stmt)).scalar_one_or_none()


async def redemption_by_user(
    session: AsyncSession, promocode_id: UUID, user_id: UUID
) -> PromocodeRedemption | None:
    stmt = select(PromocodeRedemption).where(
        PromocodeRedemption.promocode_id == promocode_id,
        PromocodeRedemption.user_id == user_id,
    )
    return (await session.execute(stmt)).scalar_one_or_none()


async def list_active_for_user(session: AsyncSession, user_id: UUID) -> list[Promocode]:
    """Возвращает промокоды, которые юзер может использовать: адресные (owner=user)
    ещё не использованные + публичные (owner=NULL) активные."""
    stmt = (
        select(Promocode)
        .where(
            or_(
                Promocode.owner_user_id == user_id,
                Promocode.owner_user_id.is_(None),
            )
        )
        .order_by(Promocode.created_at.desc())
    )
    return list((await session.execute(stmt)).scalars())


async def list_all(session: AsyncSession, kind: PromocodeKind | None = None) -> list[Promocode]:
    stmt = select(Promocode).order_by(Promocode.created_at.desc())
    if kind is not None:
        stmt = stmt.where(Promocode.kind == kind)
    return list((await session.execute(stmt)).scalars())


async def count_referrals(session: AsyncSession, referrer_id: UUID) -> int:
    """Сколько юзеров зарегистрировались с invited_by_user_id = referrer_id."""
    from app.domain.models import User
    stmt = select(func.count()).select_from(User).where(User.invited_by_user_id == referrer_id)
    return int((await session.execute(stmt)).scalar_one())


async def sum_referral_rewards(session: AsyncSession, owner_user_id: UUID) -> int:
    """Сумма всех использованных скидок по промокодам, где owner = юзер (REFERRAL)."""
    stmt = (
        select(func.coalesce(func.sum(PromocodeRedemption.discount_applied_kopecks), 0))
        .join(Promocode, Promocode.id == PromocodeRedemption.promocode_id)
        .where(Promocode.owner_user_id == owner_user_id)
    )
    return int((await session.execute(stmt)).scalar_one())


async def create(session: AsyncSession, promocode: Promocode) -> Promocode:
    session.add(promocode)
    await session.flush()
    return promocode


async def create_redemption(
    session: AsyncSession, redemption: PromocodeRedemption
) -> PromocodeRedemption:
    session.add(redemption)
    await session.flush()
    return redemption


async def list_redemptions(
    session: AsyncSession, promocode_id: UUID
) -> list[PromocodeRedemption]:
    stmt = (
        select(PromocodeRedemption)
        .where(PromocodeRedemption.promocode_id == promocode_id)
        .order_by(PromocodeRedemption.redeemed_at.desc())
    )
    return list((await session.execute(stmt)).scalars())
