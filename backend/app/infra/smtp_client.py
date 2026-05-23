from email.message import EmailMessage

import aiosmtplib

from app.core.config import settings
from app.core.errors import ExternalServiceError
from app.core.logging import logger


async def send_email(
    to: str,
    subject: str,
    text: str,
    html: str | None = None,
) -> None:
    msg = EmailMessage()
    msg["From"] = f"{settings.SMTP_FROM_NAME} <{settings.SMTP_FROM}>"
    msg["To"] = to
    msg["Subject"] = subject
    msg.set_content(text)
    if html:
        msg.add_alternative(html, subtype="html")

    try:
        await aiosmtplib.send(
            msg,
            hostname=settings.SMTP_HOST,
            port=settings.SMTP_PORT,
            username=settings.SMTP_USER or None,
            password=settings.SMTP_PASSWORD.get_secret_value() or None,
            use_tls=settings.SMTP_TLS,
            timeout=10,
        )
        logger.info("email_sent", to=to, subject=subject)
    except Exception as exc:
        logger.error("email_send_failed", to=to, error=str(exc))
        raise ExternalServiceError("SMTP send failed") from exc
