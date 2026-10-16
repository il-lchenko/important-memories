from uuid import UUID

from fastapi import APIRouter
from fastapi.responses import Response

from app.api.deps import CurrentUserId, SessionDep
from app.domain.schemas.collections import (
    CollectionCreateIn,
    CollectionItemsIn,
    CollectionOut,
    CollectionsListOut,
)
from app.services import collection_service

router = APIRouter()


@router.get("/", response_model=CollectionsListOut)
async def list_collections(user_id: CurrentUserId, session: SessionDep) -> CollectionsListOut:
    return await collection_service.list_collections(session, user_id)


@router.post("/", response_model=CollectionOut, status_code=201)
async def create_collection(
    payload: CollectionCreateIn, user_id: CurrentUserId, session: SessionDep
) -> CollectionOut:
    return await collection_service.create_collection(session, user_id, payload.title)


@router.get("/{collection_id}", response_model=CollectionOut)
async def get_collection(collection_id: UUID, user_id: CurrentUserId, session: SessionDep) -> CollectionOut:
    return await collection_service.get_collection(session, user_id, collection_id)


@router.patch("/{collection_id}", status_code=204)
async def rename_collection(
    collection_id: UUID, payload: CollectionCreateIn, user_id: CurrentUserId, session: SessionDep
) -> Response:
    await collection_service.rename_collection(session, user_id, collection_id, payload.title)
    return Response(status_code=204)


@router.delete("/{collection_id}", status_code=204)
async def delete_collection(collection_id: UUID, user_id: CurrentUserId, session: SessionDep) -> Response:
    await collection_service.delete_collection(session, user_id, collection_id)
    return Response(status_code=204)


@router.post("/{collection_id}/items", response_model=CollectionOut)
async def add_items(
    collection_id: UUID, payload: CollectionItemsIn, user_id: CurrentUserId, session: SessionDep
) -> CollectionOut:
    await collection_service.add_items(session, user_id, collection_id, payload.frame_ids)
    return await collection_service.get_collection(session, user_id, collection_id)


@router.delete("/{collection_id}/items/{frame_id}", status_code=204)
async def remove_item(
    collection_id: UUID, frame_id: UUID, user_id: CurrentUserId, session: SessionDep
) -> Response:
    await collection_service.remove_item(session, user_id, collection_id, frame_id)
    return Response(status_code=204)
