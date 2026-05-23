from fastapi import APIRouter

from app.api.deps import CurrentUserId, SessionDep
from app.domain.schemas.devices import DeviceOut, DeviceRegisterIn
from app.repos import device_repo

router = APIRouter()


@router.post("/", response_model=DeviceOut, status_code=201)
async def register_device(
    payload: DeviceRegisterIn,
    user_id: CurrentUserId,
    session: SessionDep,
) -> DeviceOut:
    device = await device_repo.upsert(session, user_id, payload.platform, payload.token)
    await session.commit()
    return DeviceOut(id=device.id, platform=device.platform)
