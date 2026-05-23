from uuid import UUID

from sqlalchemy.ext.asyncio import AsyncSession

from app.core.errors import NotFoundError
from app.domain.models import Report, ReportStatus
from app.domain.models.enums import ReportCategory
from app.domain.schemas.reports import ReportOut
from app.repos import event_repo, frame_repo


async def create_report(
    session: AsyncSession,
    *,
    actor_user_id: UUID | None,
    actor_guest_id: UUID | None,
    frame_id: UUID | None,
    event_id: UUID | None,
    category: ReportCategory,
    note: str | None,
) -> ReportOut:
    if frame_id is not None:
        frame = await frame_repo.get_by_id(session, frame_id)
        if frame is None:
            raise NotFoundError("Frame not found")
        event_id = event_id or frame.event_id
    if event_id is not None:
        event = await event_repo.get_by_id(session, event_id)
        if event is None:
            raise NotFoundError("Event not found")

    report = Report(
        frame_id=frame_id,
        event_id=event_id,
        reporter_user_id=actor_user_id,
        reporter_guest_id=actor_guest_id,
        category=category,
        note=note,
        status=ReportStatus.OPEN,
    )
    session.add(report)
    await session.commit()
    await session.refresh(report)
    return ReportOut(id=report.id, status=report.status.value)
