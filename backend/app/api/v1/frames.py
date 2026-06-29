from uuid import UUID

from fastapi import APIRouter, Response

from app.api.deps import CurrentGuest, SessionDep
from app.domain.schemas.frames import (
    FramePresignIn,
    FramePresignOut,
    FrameRegisterIn,
    FrameRegisterOut,
    FrameUpdateIn,
    FrameVoicePresignIn,
    FrameVoicePresignOut,
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


@router.post("/{frame_id}/voice-presign", response_model=FrameVoicePresignOut)
async def presign_voice(
    frame_id: UUID,
    payload: FrameVoicePresignIn,
    guest: CurrentGuest,
    session: SessionDep,
) -> FrameVoicePresignOut:
    return await media_service.presign_voice(
        session, guest, frame_id, payload.content_type, payload.size_bytes
    )


@router.patch("/{frame_id}", status_code=204)
async def update_frame(
    frame_id: UUID,
    payload: FrameUpdateIn,
    guest: CurrentGuest,
    session: SessionDep,
) -> Response:
    await media_service.update_frame(session, guest, frame_id, payload)
    return Response(status_code=204)
