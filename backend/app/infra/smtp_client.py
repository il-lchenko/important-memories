import httpx

from app.core.config import settings
from app.core.logging import logger


async def send_email(
    to: str,
    subject: str,
    text: str,
    html: str | None = None,
) -> None:
    payload: dict = {
        "from": f"{settings.SMTP_FROM_NAME} <{settings.SMTP_FROM}>",
        "to": [to],
        "subject": subject,
        "text": text,
    }
    if html:
        payload["html"] = html

    try:
        async with httpx.AsyncClient(timeout=10) as client:
            resp = await client.post(
                "https://api.resend.com/emails",
                json=payload,
                headers={"Authorization": f"Bearer {settings.SMTP_PASSWORD.get_secret_value()}"},
            )
            resp.raise_for_status()
        logger.info("email_sent", to=to, subject=subject)
    except Exception as exc:
        logger.error("email_send_failed", to=to, error=str(exc))
        raise
