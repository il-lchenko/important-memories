import logging
import re
from typing import Any

import structlog

from app.core.config import settings


# PII masking: log entries may contain email, otp_code, tokens.
# We rewrite these fields in-flight so raw values never hit stdout/Sentry/log files.
_PII_KEYS: set[str] = {
    "password",
    "otp_code",
    "code",
    "token",
    "access_token",
    "refresh_token",
    "guest_token",
    "jwt",
    "secret",
    "authorization",
    "webhook_signature",
    "fcm_token",
    "device_token",
}


def _mask_email(v: str) -> str:
    """Turn 'ilya@example.com' into 'i***@example.com'."""
    if "@" not in v:
        return "***"
    local, _, domain = v.partition("@")
    if not local:
        return f"***@{domain}"
    return f"{local[0]}***@{domain}"


def _mask_value(key: str, value: Any) -> Any:
    if isinstance(value, str):
        klow = key.lower()
        if klow == "email" or klow == "to":
            return _mask_email(value)
        if klow in _PII_KEYS:
            # Show first 4 chars for debugging, hide rest
            return f"{value[:4]}***" if len(value) > 4 else "***"
    return value


def _pii_scrub(_logger: Any, _method: str, event_dict: dict[str, Any]) -> dict[str, Any]:
    """Structlog processor: mask any PII fields before rendering."""
    return {k: _mask_value(k, v) for k, v in event_dict.items()}


def configure_logging() -> None:
    logging.basicConfig(
        format="%(message)s",
        level=settings.LOG_LEVEL,
    )
    structlog.configure(
        processors=[
            structlog.contextvars.merge_contextvars,
            structlog.processors.add_log_level,
            structlog.processors.TimeStamper(fmt="iso"),
            structlog.processors.StackInfoRenderer(),
            structlog.processors.format_exc_info,
            _pii_scrub,
            structlog.processors.JSONRenderer()
            if settings.APP_ENV != "local"
            else structlog.dev.ConsoleRenderer(),
        ],
        wrapper_class=structlog.make_filtering_bound_logger(
            getattr(logging, settings.LOG_LEVEL, logging.INFO)
        ),
        cache_logger_on_first_use=True,
    )


logger = structlog.get_logger()
