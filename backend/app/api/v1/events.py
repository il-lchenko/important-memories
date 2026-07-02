from typing import Annotated
from uuid import UUID, uuid4

from fastapi import APIRouter, Header, Query, UploadFile, File
from fastapi.responses import Response

from app.api.deps import CurrentActor, CurrentUserId, SessionDep
from app.core.errors import AuthError, NotFoundError
from app.domain.schemas.album import AlbumOut
from app.domain.schemas.archives import ArchiveJobOut
from app.domain.schemas.events import (
    EventCreateIn,
    EventOut,
    EventRenameIn,
    EventSettingsUpdateIn,
    EventUpdateIn,
)
from app.domain.schemas.frames import FrameRotationIn
from app.domain.schemas.guests import InvitedEventOut
from app.repos import guest_repo
from app.domain.schemas.payments import CheckoutIn, CheckoutOut, ExtendIn, ExtendOut, UpgradeIn, UpgradeOut
from app.infra import queue
from app.services import album_service, event_service, media_service, payment_service
from app.services.event_service import _resolve_cover_url

router = APIRouter()


@router.post("/", response_model=EventOut, status_code=201)
async def create_event(
    payload: EventCreateIn,
    user_id: CurrentUserId,
    session: SessionDep,
) -> EventOut:
    return await event_service.create_event(session, user_id, payload)


@router.get("/", response_model=list[EventOut])
async def list_events(
    user_id: CurrentUserId,
    session: SessionDep,
) -> list[EventOut]:
    return await event_service.list_events(session, user_id)


@router.get("/invited", response_model=list[InvitedEventOut])
async def list_invited_events(
    user_id: CurrentUserId,
    session: SessionDep,
) -> list[InvitedEventOut]:
    """События где юзер был приглашён (invited guest), исключая собственные."""
    rows = await guest_repo.list_invited_events_for_user(session, user_id, exclude_owned=True)
    return [
        InvitedEventOut(
            id=event.id,
            short_code=event.short_code,
            title=event.title,
            status=event.status.value,
            start_at=event.start_at,
            end_at=event.end_at,
            cover_url=_resolve_cover_url(event.cover_url),
            my_frames_count=my_count,
            total_frames=total_count,
        )
        for event, my_count, total_count in rows
    ]


@router.get("/{event_id}", response_model=EventOut)
async def get_event(
    event_id: UUID,
    user_id: CurrentUserId,
    session: SessionDep,
) -> EventOut:
    return await event_service.get_event(session, user_id, event_id)


@router.patch("/{event_id}", response_model=EventOut)
async def update_event(
    event_id: UUID,
    payload: EventUpdateIn,
    user_id: CurrentUserId,
    session: SessionDep,
) -> EventOut:
    return await event_service.update_event(session, user_id, event_id, payload)


@router.delete("/{event_id}", status_code=204)
async def delete_event(
    event_id: UUID,
    user_id: CurrentUserId,
    session: SessionDep,
) -> Response:
    await event_service.cancel_event(session, user_id, event_id)
    return Response(status_code=204)


@router.patch("/{event_id}/settings", response_model=EventOut)
async def update_settings(
    event_id: UUID,
    payload: EventSettingsUpdateIn,
    user_id: CurrentUserId,
    session: SessionDep,
) -> EventOut:
    return await event_service.update_settings(session, user_id, event_id, payload)


@router.post("/{event_id}/activate", response_model=EventOut)
async def activate_event(
    event_id: UUID,
    user_id: CurrentUserId,
    session: SessionDep,
) -> EventOut:
    return await event_service.activate_event(session, user_id, event_id)


@router.post("/{event_id}/complete", response_model=EventOut)
async def complete_event(
    event_id: UUID,
    user_id: CurrentUserId,
    session: SessionDep,
) -> EventOut:
    return await event_service.complete_event(session, user_id, event_id)


@router.post("/{event_id}/checkout", response_model=CheckoutOut)
async def create_checkout(
    event_id: UUID,
    payload: CheckoutIn,
    user_id: CurrentUserId,
    session: SessionDep,
    idempotency_key: Annotated[str | None, Header(alias="Idempotency-Key")] = None,
) -> CheckoutOut:
    key = idempotency_key or str(uuid4())
    return await payment_service.create_checkout(session, user_id, event_id, payload.plan, key)


@router.post("/{event_id}/extend", response_model=ExtendOut)
async def extend_storage(
    event_id: UUID,
    payload: ExtendIn,
    user_id: CurrentUserId,
    session: SessionDep,
    idempotency_key: Annotated[str | None, Header(alias="Idempotency-Key")] = None,
) -> ExtendOut:
    """Create a YooKassa checkout to extend album storage by 3m/6m/1y.

    expires_at is updated only after webhook confirms the payment (see handle_webhook).
    """
    key = idempotency_key or str(uuid4())
    return await payment_service.create_extend_checkout(
        session, user_id, event_id, payload.period, key
    )


@router.post("/{event_id}/upgrade", response_model=UpgradeOut)
async def upgrade_event(
    event_id: UUID,
    payload: UpgradeIn,
    user_id: CurrentUserId,
    session: SessionDep,
    idempotency_key: Annotated[str | None, Header(alias="Idempotency-Key")] = None,
) -> UpgradeOut:
    """Create a YooKassa checkout to upgrade an event.

    kind="guests" — bump to next-tier plan (P10→P25→P50→...).
    kind="frames" — extend frames_per_guest from 30 to 45 (+5 ₽/guest).
    Changes applied after webhook confirms payment.
    """
    key = idempotency_key or str(uuid4())
    return await payment_service.create_upgrade_checkout(
        session, user_id, event_id, payload.kind, key
    )


@router.get("/{event_id}/qr", responses={200: {"content": {"image/png": {}}}})
async def get_qr(
    event_id: UUID,
    user_id: CurrentUserId,
    session: SessionDep,
) -> Response:
    _, png_bytes = await event_service.generate_qr(session, user_id, event_id)
    return Response(content=png_bytes, media_type="image/png")


@router.post("/{event_id}/reveal", response_model=EventOut)
async def reveal_event(
    event_id: UUID,
    user_id: CurrentUserId,
    session: SessionDep,
) -> EventOut:
    return await event_service.reveal_event(session, user_id, event_id)


@router.get("/{event_id}/album", response_model=AlbumOut)
async def get_album(
    event_id: UUID,
    actor: CurrentActor,
    session: SessionDep,
    cursor: str | None = Query(default=None),
    limit: int = Query(default=30, ge=1, le=100),
) -> AlbumOut:
    if actor.user_id is None and actor.guest is None:
        raise AuthError("Authentication required")
    return await album_service.get_album(
        session,
        event_id,
        actor_user_id=actor.user_id,
        actor_guest_id=actor.guest.id if actor.guest else None,
        cursor=cursor,
        limit=limit,
    )


@router.delete("/{event_id}/frames/{frame_id}", status_code=204)
async def delete_frame(
    event_id: UUID,
    frame_id: UUID,
    actor: CurrentActor,
    session: SessionDep,
) -> Response:
    await media_service.delete_frame(
        session,
        frame_id,
        actor_user_id=actor.user_id,
        actor_guest_id=actor.guest.id if actor.guest else None,
    )
    return Response(status_code=204)


@router.patch("/{event_id}/frames/{frame_id}/rotation", status_code=204)
async def update_frame_rotation(
    event_id: UUID,
    frame_id: UUID,
    payload: FrameRotationIn,
    user_id: CurrentUserId,
    session: SessionDep,
) -> Response:
    await media_service.update_rotation(
        session,
        actor_user_id=user_id,
        event_id=event_id,
        frame_id=frame_id,
        rotation=payload.rotation,
    )
    return Response(status_code=204)


@router.post("/{event_id}/cover", response_model=EventOut)
async def upload_cover(
    event_id: UUID,
    user_id: CurrentUserId,
    session: SessionDep,
    file: UploadFile = File(...),
) -> EventOut:
    data = await file.read()
    return await event_service.upload_cover(
        session, user_id, event_id, data, file.content_type or "image/jpeg"
    )


@router.post("/{event_id}/download", response_model=ArchiveJobOut, status_code=202)
async def request_download(
    event_id: UUID,
    user_id: CurrentUserId,
    session: SessionDep,
) -> ArchiveJobOut:
    await event_service.get_event(session, user_id, event_id)
    job_id = uuid4().hex
    await queue.build_zip(event_id, job_id)
    return ArchiveJobOut(job_id=job_id, status="pending")


@router.get("/{event_id}/download/{job_id}", response_model=ArchiveJobOut)
async def download_status(
    event_id: UUID,
    job_id: str,
    user_id: CurrentUserId,
    session: SessionDep,
) -> ArchiveJobOut:
    await event_service.get_event(session, user_id, event_id)
    info = await queue.get_job_status(job_id)
    if info is None:
        raise NotFoundError("Archive job not found")
    if info.get("status") == "failed":
        return ArchiveJobOut(job_id=job_id, status="failed")
    result = info.get("result") or {}
    if isinstance(result, dict) and result.get("status") in {"ready", "empty"}:
        return ArchiveJobOut(
            job_id=job_id,
            status=result["status"],
            download_url=result.get("download_url"),
            frame_count=result.get("frame_count"),
        )
    return ArchiveJobOut(job_id=job_id, status="pending")
