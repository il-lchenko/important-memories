from fastapi import APIRouter

from app.api.deps import CurrentUserId, SessionDep
from app.domain.schemas.memories import MemoriesOut
from app.services import memories_service

router = APIRouter()


@router.get("/", response_model=MemoriesOut)
async def get_memories(user_id: CurrentUserId, session: SessionDep) -> MemoriesOut:
    """Ленту раздела «Кадры» — блоки с типами: tilted, collage_a..e, grid_6."""
    return await memories_service.build_memories_feed(session, user_id)
