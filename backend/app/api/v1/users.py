from fastapi import APIRouter
from pydantic import BaseModel, ConfigDict, Field

from app.api.deps import CurrentUserId, SessionDep
from app.core.errors import NotFoundError
from app.repos import user_repo

router = APIRouter()


class UserOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    email: str
    display_name: str | None


class UserUpdateIn(BaseModel):
    display_name: str | None = Field(default=None, max_length=120)


@router.get("/me", response_model=UserOut)
async def get_me(user_id: CurrentUserId, session: SessionDep) -> UserOut:
    user = await user_repo.get_by_id(session, user_id)
    if user is None:
        raise NotFoundError("User not found")
    return UserOut(email=user.email, display_name=user.display_name)


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
    await session.flush()
    await session.commit()
    return UserOut(email=user.email, display_name=user.display_name)
