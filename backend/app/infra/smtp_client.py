"""Клиент отправки транзакционных писем.

Приоритет провайдеров:
1. Unisender (РФ-резидент, https://godocs.unisender.ru/transactional-api) —
   если задан UNISENDER_API_KEY. Основной путь на продакшене.
2. Local SMTP (для dev-окружения через MailHog / Mailtrap) — если задан
   SMTP_HOST и не задан UNISENDER_API_KEY.

Трансграничная передача персональных данных не осуществляется.
"""
import asyncio
from email.message import EmailMessage
from email.utils import formataddr

import httpx

from app.core.config import settings
from app.core.logging import logger


_UNISENDER_URL = "https://go1.unisender.ru/ru/transactional/api/v1/email/send.json"


async def send_email(
    to: str,
    subject: str,
    text: str,
    html: str | None = None,
) -> None:
    api_key = settings.UNISENDER_API_KEY.get_secret_value().strip()
    if api_key:
        await _send_via_unisender(api_key, to, subject, text, html)
        return

    # Legacy / dev fallback — локальный SMTP.
    await _send_via_smtp(to, subject, text, html)


async def _send_via_unisender(
    api_key: str,
    to: str,
    subject: str,
    text: str,
    html: str | None,
) -> None:
    body: dict = {"plaintext": text}
    if html:
        body["html"] = html
    payload: dict = {
        "message": {
            "recipients": [{"email": to}],
            "body": body,
            "subject": subject,
            "from_email": settings.UNISENDER_FROM_EMAIL,
            "from_name": settings.UNISENDER_FROM_NAME,
            "reply_to": settings.UNISENDER_REPLY_TO,
        }
    }
    try:
        async with httpx.AsyncClient(timeout=10) as client:
            resp = await client.post(
                _UNISENDER_URL,
                json=payload,
                headers={
                    "X-API-KEY": api_key,
                    "Content-Type": "application/json",
                },
            )
            resp.raise_for_status()
        # Не логируем email как PII — берём только домен.
        domain = to.split("@", 1)[1] if "@" in to else "unknown"
        logger.info("email_sent", provider="unisender", to_domain=domain, subject=subject)
    except httpx.HTTPStatusError as exc:
        # Unisender возвращает подробности ошибки в теле — но там может быть email адрес,
        # который мы не хотим логировать. Логируем только статус.
        logger.error(
            "email_send_failed",
            provider="unisender",
            status=exc.response.status_code,
        )
        raise
    except Exception as exc:  # noqa: BLE001
        logger.error("email_send_failed", provider="unisender", error_type=type(exc).__name__)
        raise


async def _send_via_smtp(
    to: str,
    subject: str,
    text: str,
    html: str | None,
) -> None:
    """Локальная отправка через smtplib — для dev-окружения (MailHog и т. п.)."""
    def _blocking_send() -> None:
        import smtplib

        msg = EmailMessage()
        msg["From"] = formataddr((settings.SMTP_FROM_NAME, settings.SMTP_FROM))
        msg["To"] = to
        msg["Subject"] = subject
        msg.set_content(text)
        if html:
            msg.add_alternative(html, subtype="html")
        with smtplib.SMTP(settings.SMTP_HOST, settings.SMTP_PORT, timeout=10) as srv:
            if settings.SMTP_TLS:
                srv.starttls()
            if settings.SMTP_USER:
                srv.login(settings.SMTP_USER, settings.SMTP_PASSWORD.get_secret_value())
            srv.send_message(msg)

    try:
        await asyncio.get_running_loop().run_in_executor(None, _blocking_send)
        domain = to.split("@", 1)[1] if "@" in to else "unknown"
        logger.info("email_sent", provider="smtp", to_domain=domain, subject=subject)
    except Exception as exc:  # noqa: BLE001
        logger.error("email_send_failed", provider="smtp", error_type=type(exc).__name__)
        raise
