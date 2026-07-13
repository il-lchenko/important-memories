"""Публичные эндпоинты — без авторизации. Read-only альбом по share-токену."""
from fastapi import APIRouter, Query

from app.api.deps import SessionDep
from app.domain.schemas.album import AlbumOut
from app.services import album_service


router = APIRouter()


@router.get("/albums/{token}")
async def get_public_album_meta(token: str, session: SessionDep) -> dict:
    return await album_service.get_public_meta(session, token)


@router.get("/albums/{token}/frames", response_model=AlbumOut)
async def list_public_album_frames(
    token: str,
    session: SessionDep,
    cursor: str | None = Query(default=None),
    limit: int = Query(default=30, ge=1, le=100),
) -> AlbumOut:
    return await album_service.get_public_album(
        session, token, cursor=cursor, limit=limit
    )
