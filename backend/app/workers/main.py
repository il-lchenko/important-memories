"""ARQ worker entry point.

Run with:
    uv run python -m app.workers.main

(Avoids importing arq.cli before we set the Windows event-loop policy.)
"""

import asyncio
import sys

if sys.platform == "win32":
    asyncio.set_event_loop_policy(asyncio.WindowsSelectorEventLoopPolicy())

from arq import cron, run_worker
from arq.connections import RedisSettings

from app.core.config import settings
from app.core.logging import configure_logging, logger
from app.workers.cleanup import cleanup_expired_frames, retry_failed_uploads
from app.workers.notifications import notify_expiring_events
from app.workers.reveal import execute_reveal
from app.workers.thumbnail import make_thumbnail
from app.workers.zip_builder import build_zip


def _redis_settings() -> RedisSettings:
    url = settings.REDIS_URL.replace("redis://", "")
    host_port, _, db = url.partition("/")
    host, _, port = host_port.partition(":")
    return RedisSettings(host=host, port=int(port or 6379), database=int(db or 0))


class WorkerSettings:
    functions = [make_thumbnail, execute_reveal, build_zip]
    cron_jobs = [
        cron(retry_failed_uploads, minute={0, 10, 20, 30, 40, 50}, run_at_startup=False),
        cron(cleanup_expired_frames, hour={3}, minute={0}, run_at_startup=False),
        # Daily at 12:00 UTC (15:00 MSK) — enough headroom for late-night morning check.
        cron(notify_expiring_events, hour={12}, minute={0}, run_at_startup=False),
    ]
    redis_settings = _redis_settings()
    keep_result = 7 * 24 * 3600
    max_jobs = 10
    job_timeout = 600


def main() -> None:
    configure_logging()
    logger.info("worker_starting")
    run_worker(WorkerSettings)


if __name__ == "__main__":
    main()
