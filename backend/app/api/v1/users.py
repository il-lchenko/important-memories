from fastapi import APIRouter, Response, status
from pydantic import BaseModel, ConfigDict, Field

from app.api.deps import CurrentUserId, SessionDep
from app.core.config import settings
from app.core.errors import ConflictError, NotFoundError
from app.infra import s3_client
from app.repos import user_repo
from app.services.guest_service import _avatar_ext_for_ct

router = APIRouter()

_AVATAR_URL_TTL = 86400  # 24h


class UserOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    email: str
    display_name: str | None
    avatar_url: str | None = None


class UserUpdateIn(BaseModel):
    display_name: str | None = Field(default=None, max_length=120)
    avatar_key: str | None = Field(default=None, max_length=512)


class AvatarPresignIn(BaseModel):
    content_type: str = Field(..., max_length=64)
    size_bytes: int = Field(..., ge=1, le=2 * 1024 * 1024)


class AvatarPresignOut(BaseModel):
    avatar_key: str
    upload_url: str
    expires_in: int


def _user_out(user) -> UserOut:
    avatar_url = (
        s3_client.presign_get(user.avatar_key, expires_in=_AVATAR_URL_TTL)
        if user.avatar_key
        else None
    )
    return UserOut(
        email=user.email,
        display_name=user.display_name,
        avatar_url=avatar_url,
    )


@router.get("/me", response_model=UserOut)
async def get_me(user_id: CurrentUserId, session: SessionDep) -> UserOut:
    user = await user_repo.get_by_id(session, user_id)
    if user is None:
        raise NotFoundError("User not found")
    return _user_out(user)


@router.patch("/me", response_model=UserOut)
async def update_me(
    payload: UserUpdateIn,
    user_id: CurrentUserId,
    session: SessionDep,
) -> UserOut:
    user = await user_repo.get_by_id(session, user_id)
    if user is None:
        raise NotFoundError("User not found")
    if payload.display_name is not None:
        user.display_name = payload.display_name.strip() or None
    if payload.avatar_key is not None:
        # Валидация: ключ должен быть в директории аватара этого пользователя.
        expected_prefix = f"avatars/users/{user.id}."
        if not payload.avatar_key.startswith(expected_prefix):
            raise ConflictError("Invalid avatar key", details={"field": "avatar_key"})
        user.avatar_key = payload.avatar_key
        # Синхронизируем с гостевыми записями этого юзера, чтобы новый аватар
        # появился в списках гостей и на подписи к фото сразу.
        from sqlalchemy import update
        from app.domain.models import Guest
        await session.execute(
            update(Guest).where(Guest.user_id == user.id).values(avatar_key=payload.avatar_key)
        )
    await session.flush()
    await session.commit()
    return _user_out(user)


@router.post("/me/avatar/presign", response_model=AvatarPresignOut)
async def presign_avatar(
    payload: AvatarPresignIn,
    user_id: CurrentUserId,
    session: SessionDep,
) -> AvatarPresignOut:
    user = await user_repo.get_by_id(session, user_id)
    if user is None:
        raise NotFoundError("User not found")
    ext = _avatar_ext_for_ct(payload.content_type)
    key = f"avatars/users/{user.id}.{ext}"
    upload_url = s3_client.presign_put(key, payload.content_type)
    return AvatarPresignOut(
        avatar_key=key,
        upload_url=upload_url,
        expires_in=settings.S3_PRESIGN_TTL_SEC,
    )


@router.delete("/me", status_code=status.HTTP_204_NO_CONTENT)
async def delete_me(user_id: CurrentUserId, session: SessionDep) -> Response:
    """Полное удаление аккаунта. Требование сторов (RuStore / Google Play).

    События, кадры, архивы, устройства удаляются каскадом (ondelete=CASCADE).
    Гостевые записи и платежи — SET NULL (сохраняются как «удалённый юзер»
    для отчётности НПД).
    S3-объекты остаются orphaned — их подчищает фоновый cron cleanup.
    """
    user = await user_repo.get_by_id(session, user_id)
    if user is None:
        raise NotFoundError("User not found")
    await session.delete(user)
    await session.commit()
    return Response(status_code=status.HTTP_204_NO_CONTENT)
