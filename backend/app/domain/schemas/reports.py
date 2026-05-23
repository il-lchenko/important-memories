from uuid import UUID

from pydantic import BaseModel, Field, model_validator

from app.domain.models.enums import ReportCategory


class ReportCreateIn(BaseModel):
    frame_id: UUID | None = None
    event_id: UUID | None = None
    category: ReportCategory
    note: str | None = Field(default=None, max_length=2000)

    @model_validator(mode="after")
    def _need_target(self) -> "ReportCreateIn":
        if self.frame_id is None and self.event_id is None:
            raise ValueError("frame_id or event_id is required")
        return self


class ReportOut(BaseModel):
    id: UUID
    status: str
