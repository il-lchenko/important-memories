from fastapi import APIRouter

from app.api.deps import CurrentUserId, SessionDep
from app.core.errors import NotFoundError
from app.domain.schemas.entitlements import EntitlementsOut
from app.repos import user_repo
from app.services import entitlement_service

router = APIRouter()


@router.get("/entitlements", response_model=EntitlementsOut)
async def get_entitlements(user_id: CurrentUserId, session: SessionDep) -> EntitlementsOut:
    user = await user_repo.get_by_id(session, user_id)
    if user is None:
        raise NotFoundError("User not found")
    return await entitlement_service.get_entitlements(session, user)
