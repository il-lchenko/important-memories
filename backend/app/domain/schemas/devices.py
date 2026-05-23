from uuid import UUID

from pydantic import BaseModel, Field

from app.domain.models.enums import Platform


class DeviceRegisterIn(BaseModel):
    platform: Platform
    token: str = Field(min_length=8, max_length=512)


class DeviceOut(BaseModel):
    id: UUID
    platform: Platform
