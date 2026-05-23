from app.core.errors import RateLimitError
from app.core.redis import get_redis


async def check_and_incr(key: str, limit: int, window_sec: int) -> int:
    """Sliding window via INCR + EXPIRE. Returns new counter value.

    Raises RateLimitError if counter > limit.
    """
    redis = get_redis()
    pipe = redis.pipeline()
    pipe.incr(key)
    pipe.expire(key, window_sec, nx=True)
    count, _ = await pipe.execute()
    if int(count) > limit:
        raise RateLimitError(
            "Too many requests",
            details={"limit": limit, "window_sec": window_sec},
        )
    return int(count)


async def too_soon(key: str, cooldown_sec: int) -> bool:
    """Atomic SET-NX with TTL. Returns True if action must be blocked."""
    redis = get_redis()
    acquired = await redis.set(key, "1", ex=cooldown_sec, nx=True)
    return not bool(acquired)
