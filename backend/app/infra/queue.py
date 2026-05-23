from datetime import datetime
from typing import Any
from uuid import UUID

from arq import create_pool
from arq.connections import ArqRedis

from app.workers.main import WorkerSettings

_pool: ArqRedis | None = None


async def get_pool() -> ArqRedis:
    global _pool
    if _pool is None:
        _pool = await create_pool(WorkerSettings.redis_settings)
    return _pool


async def enqueue(function_name: str, *args: Any, **kwargs: Any) -> str | None:
    pool = await get_pool()
    job = await pool.enqueue_job(function_name, *args, **kwargs)
    return job.job_id if job else None


async def schedule_at(function_name: str, when: datetime, *args: Any, **kwargs: Any) -> str | None:
    pool = await get_pool()
    job = await pool.enqueue_job(function_name, *args, _defer_until=when, **kwargs)
    return job.job_id if job else None


async def close_pool() -> None:
    global _pool
    if _pool is not None:
        await _pool.aclose()
        _pool = None


async def make_thumbnail(frame_id: UUID) -> None:
    await enqueue("make_thumbnail", str(frame_id))


async def schedule_reveal(event_id: UUID, when: datetime) -> None:
    await schedule_at("execute_reveal", when, str(event_id))


async def build_zip(event_id: UUID, job_id: str) -> None:
    await enqueue("build_zip", str(event_id), job_id)


async def get_job_status(job_id: str) -> dict[str, Any] | None:
    pool = await get_pool()
    from arq.jobs import Job

    job = Job(job_id, pool)
    info = await job.info()
    if info is None:
        return None
    try:
        result = await job.result(timeout=0.1)
    except Exception:
        result = None
    return {"status": str(info.status) if hasattr(info, "status") else "queued", "result": result}
