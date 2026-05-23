from fastapi import APIRouter

from app.api.deps import CurrentGuest, SessionDep
from app.domain.schemas.frames import (
    FramePresignIn,
    FramePresignOut,
    FrameRegisterIn,
    FrameRegisterOut,
)
from app.services import media_service

router = APIRouter()


@router.post("/presign", response_model=FramePresignOut)
async def presign_frame(
    payload: FramePresignIn,
    guest: CurrentGuest,
    session: SessionDep,
) -> FramePresignOut:
    return await media_service.presign_upload(
        session, guest, payload.content_type, payload.size_bytes
    )


@router.post("/", response_model=FrameRegisterOut, status_code=201)
async def register_frame(
    payload: FrameRegisterIn,
    guest: CurrentGuest,
    session: SessionDep,
) -> FrameRegisterOut:
    return await media_service.register_frame(
        session,
        guest,
        frame_id=payload.frame_id,
        captured_at=payload.captured_at,
        width=payload.width,
        height=payload.height,
    )
