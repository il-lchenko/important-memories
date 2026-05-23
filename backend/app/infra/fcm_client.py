"""Minimal Firebase Cloud Messaging (HTTP v1) client.

Gracefully skips all operations when FCM is not configured
(FCM_PROJECT_ID empty or FCM_CREDENTIALS_JSON empty).
"""

import json
import logging
from typing import Any

import httpx
from google.oauth2 import service_account
from google.auth.transport.requests import Request as GoogleRequest

from app.core.config import settings

logger = logging.getLogger(__name__)

_FCM_SCOPE = "https://www.googleapis.com/auth/firebase.messaging"
_credentials: service_account.Credentials | None = None


def _get_credentials() -> service_account.Credentials | None:
    global _credentials
    if _credentials is not None:
        return _credentials
    creds_json = settings.FCM_CREDENTIALS_JSON.get_secret_value()
    if not settings.FCM_PROJECT_ID or not creds_json:
        return None
    try:
        info = json.loads(creds_json)
        _credentials = service_account.Credentials.from_service_account_info(
            info, scopes=[_FCM_SCOPE]
        )
    except Exception:
        logger.exception("FCM credentials parse failed")
        return None
    return _credentials


def _access_token() -> str | None:
    creds = _get_credentials()
    if creds is None:
        return None
    if not creds.valid or creds.expired:
        try:
            creds.refresh(GoogleRequest())
        except Exception:
            logger.exception("FCM token refresh failed")
            return None
    return creds.token


async def send(
    *,
    token: str,
    title: str,
    body: str,
    data: dict[str, str] | None = None,
) -> bool:
    """Send FCM push to a single device token. Returns True on success."""
    access_token = _access_token()
    if access_token is None:
        return False

    url = f"https://fcm.googleapis.com/v1/projects/{settings.FCM_PROJECT_ID}/messages:send"
    message: dict[str, Any] = {
        "token": token,
        "notification": {"title": title, "body": body},
    }
    if data:
        message["data"] = data

    try:
        async with httpx.AsyncClient(timeout=10) as client:
            resp = await client.post(
                url,
                json={"message": message},
                headers={"Authorization": f"Bearer {access_token}"},
            )
            if resp.status_code == 200:
                return True
            logger.warning("fcm_send_failed", status=resp.status_code, body=resp.text[:200])
    except Exception:
        logger.exception("fcm_send_error")
    return False


async def send_multicast(
    *,
    tokens: list[str],
    title: str,
    body: str,
    data: dict[str, str] | None = None,
) -> int:
    """Send to multiple tokens. Returns count of successes."""
    if not tokens:
        return 0
    results = 0
    for token in tokens:
        if await send(token=token, title=title, body=body, data=data):
            results += 1
    return results
