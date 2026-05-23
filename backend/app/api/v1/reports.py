from fastapi import APIRouter

from app.api.deps import CurrentActor, SessionDep
from app.domain.schemas.reports import ReportCreateIn, ReportOut
from app.services import report_service

router = APIRouter()


@router.post("/", response_model=ReportOut, status_code=201)
async def create_report(
    payload: ReportCreateIn,
    actor: CurrentActor,
    session: SessionDep,
) -> ReportOut:
    return await report_service.create_report(
        session,
        actor_user_id=actor.user_id,
        actor_guest_id=actor.guest.id if actor.guest else None,
        frame_id=payload.frame_id,
        event_id=payload.event_id,
        category=payload.category,
        note=payload.note,
    )
