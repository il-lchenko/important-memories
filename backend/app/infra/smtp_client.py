"""Клиент отправки транзакционных писем.

Приоритет провайдеров:
1. SMTP.bz (РФ, https://smtp.bz/, 15K/мес бесплатно, любые домены получателей) —
   если задан SMTPBZ_API_KEY. Основной путь на продакшене.
2. Unisender Go (deprecated fallback, free tier не разрешает внешние домены получателей) —
   если задан UNISENDER_API_KEY.
3. Local SMTP (dev-окружение через MailHog / smtplib) — иначе.

Трансграничная передача персональных данных не осуществляется.
"""
import asyncio
from email.message import EmailMessage
from email.utils import formataddr

import httpx

from app.core.config import settings
from app.core.logging import logger


_SMTPBZ_URL = "https://api.smtp.bz/v1/smtp/send"
_UNISENDER_URL = "https://go1.unisender.ru/ru/transactional/api/v1/email/send.json"


async def send_email(
    to: str,
    subject: str,
    text: str,
    html: str | None = None,
) -> None:
    smtpbz_key = settings.SMTPBZ_API_KEY.get_secret_value().strip()
    if smtpbz_key:
        await _send_via_smtpbz(smtpbz_key, to, subject, text, html)
        return

    unisender_key = settings.UNISENDER_API_KEY.get_secret_value().strip()
    if unisender_key:
        await _send_via_unisender(unisender_key, to, subject, text, html)
        return

    await _send_via_smtp(to, subject, text, html)


async def _send_via_smtpbz(
    api_key: str,
    to: str,
    subject: str,
    text: str,
    html: str | None,
) -> None:
    # SMTP.bz HTTP API: application/json, заголовок Authorization: <api-key>.
    # SMTP.bz требует непустой html — используем text как fallback.
    payload: dict = {
        "name": settings.SMTPBZ_FROM_NAME,
        "from": settings.SMTPBZ_FROM_EMAIL,
        "subject": subject,
        "to": to,
        "text": text,
        "html": html or f"<pre>{text}</pre>",
        "reply": settings.SMTPBZ_REPLY_TO,
    }
    try:
        async with httpx.AsyncClient(timeout=10) as client:
            resp = await client.post(
                _SMTPBZ_URL,
                json=payload,
                headers={
                    "Authorization": api_key,
                    "Content-Type": "application/json",
                },
            )
            resp.raise_for_status()
        domain = to.split("@", 1)[1] if "@" in to else "unknown"
        logger.info("email_sent", provider="smtpbz", to_domain=domain, subject=subject)
    except httpx.HTTPStatusError as exc:
        logger.error(
            "email_send_failed",
            provider="smtpbz",
            status=exc.response.status_code,
        )
        raise
    except Exception as exc:  # noqa: BLE001
        logger.error("email_send_failed", provider="smtpbz", error_type=type(exc).__name__)
        raise


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
        domain = to.split("@", 1)[1] if "@" in to else "unknown"
        logger.info("email_sent", provider="unisender", to_domain=domain, subject=subject)
    except httpx.HTTPStatusError as exc:
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
