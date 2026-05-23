from typing import Literal

from pydantic import BaseModel


class ArchiveJobOut(BaseModel):
    job_id: str
    status: Literal["pending", "ready", "empty", "failed"]
    download_url: str | None = None
    frame_count: int | None = None
