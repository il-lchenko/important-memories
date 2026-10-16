from datetime import datetime

from app.domain.models import Event, EventStatus, RevealMode


def reveal_is_due(event: Event, now: datetime) -> bool:
    """Отложенная проявка: пора открывать альбом (reveal_at наступил)."""
    s = event.settings
    return (
        s is not None
        and s.reveal_mode == RevealMode.DELAYED
        and s.reveal_at is not None
        and s.reveal_at <= now
    )


def completion_due(event: Event, now: datetime) -> bool:
    """ACTIVE-событие должно стать COMPLETED: вышел end_at или наступила проявка."""
    if event.status != EventStatus.ACTIVE:
        return False
    if event.end_at is not None and event.end_at <= now:
        return True
    return reveal_is_due(event, now)
