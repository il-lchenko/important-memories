from datetime import datetime, timedelta, timezone
from secrets import randbelow

from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.core.errors import AuthError, ConflictError, InvalidCodeError
from app.core.logging import logger
from app.core.security import (
    TokenDecodeError,
    create_access_token,
    create_refresh_token,
    decode_token,
    hash_secret,
    verify_secret,
)
from app.domain.schemas.auth import EmailRequestOut, TokenOut
from app.infra import rate_limiter
from app.infra.smtp_client import send_email
from app.repos import email_code_repo, user_repo


def _generate_code() -> str:
    return f"{randbelow(1_000_000):06d}"


def _build_email_body(code: str) -> tuple[str, str]:
    text = (
        f"Ваш код входа в Important Memories: {code}\n\n"
        f"Код действителен {settings.OTP_TTL_MIN} минут.\n"
        "Если вы не запрашивали код — просто проигнорируйте это письмо.\n"
    )
    html = f"""
<!DOCTYPE html>
<html lang="ru">
<body style="font-family: -apple-system, Segoe UI, sans-serif; max-width: 480px; margin: 0 auto; padding: 32px;">
  <h2 style="margin: 0 0 16px; color: #1a1a1a;">Important Memories</h2>
  <p style="font-size: 15px; color: #4a4a4a; margin: 0 0 24px;">Ваш код входа:</p>
  <div style="font-size: 32px; font-weight: 600; letter-spacing: 6px; padding: 16px 24px;
              background: #f3f3f5; border-radius: 12px; text-align: center; color: #1a1a1a;">
    {code}
  </div>
  <p style="font-size: 13px; color: #888; margin: 24px 0 0;">
    Код действителен {settings.OTP_TTL_MIN} минут. Если вы не запрашивали код — проигнорируйте письмо.
  </p>
</body>
</html>
""".strip()
    return text, html


async def request_otp(session: AsyncSession, email: str, client_ip: str) -> EmailRequestOut:
    email = email.lower().strip()

    if await rate_limiter.too_soon(
        f"otp:req:cd:{email}", settings.OTP_RATE_LIMIT_PER_EMAIL_SEC
    ):
        raise ConflictError(
            "Запрос кода был отправлен недавно, повторите через минуту",
            details={"retry_after_sec": settings.OTP_RATE_LIMIT_PER_EMAIL_SEC},
        )

    await rate_limiter.check_and_incr(
        f"otp:req:ip:{client_ip}",
        limit=settings.OTP_RATE_LIMIT_PER_IP_HOUR,
        window_sec=3600,
    )

    await email_code_repo.invalidate_active_for_email(session, email)

    code = _generate_code()
    expires_at = datetime.now(timezone.utc) + timedelta(minutes=settings.OTP_TTL_MIN)
    await email_code_repo.create(session, email, hash_secret(code), expires_at)
    await session.commit()

    logger.warning("otp_code_debug", email=email, code=code)

    text, html = _build_email_body(code)
    await send_email(
        to=email,
        subject=f"Код входа в Important Memories: {code}",
        text=text,
        html=html,
    )

    return EmailRequestOut(expires_in=settings.OTP_TTL_MIN * 60)


async def verify_otp(session: AsyncSession, email: str, code: str) -> TokenOut:
    email = email.lower().strip()
    active = await email_code_repo.find_active(session, email)
    if active is None:
        raise AuthError("Код не найден или истёк")

    if active.attempts >= settings.OTP_MAX_ATTEMPTS:
        raise AuthError("Превышено число попыток. Запросите новый код.")

    if not verify_secret(code, active.code_hash):
        await email_code_repo.increment_attempts(session, active)
        await session.commit()
        raise InvalidCodeError("Неверный код")

    await email_code_repo.consume(session, active)
    user, _is_new = await user_repo.get_or_create(session, email)
    await user_repo.touch_last_login(session, user)
    await session.commit()

    return TokenOut(
        access_token=create_access_token(user.id),
        refresh_token=create_refresh_token(user.id),
        user_id=user.id,
    )


async def refresh(session: AsyncSession, refresh_token: str) -> TokenOut:
    try:
        user_id = decode_token(refresh_token, expected_type="refresh")
    except TokenDecodeError as exc:
        raise AuthError(str(exc)) from exc

    user = await user_repo.get_by_id(session, user_id)
    if user is None:
        raise AuthError("Пользователь не найден")

    return TokenOut(
        access_token=create_access_token(user.id),
        refresh_token=create_refresh_token(user.id),
        user_id=user.id,
    )
