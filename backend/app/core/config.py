from functools import lru_cache
from typing import Literal

from pydantic import Field, SecretStr
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
    )

    APP_ENV: Literal["local", "staging", "production"] = "local"
    APP_NAME: str = "Important Memories API"
    APP_VERSION: str = "0.1.0"
    LOG_LEVEL: str = "INFO"

    API_V1_PREFIX: str = "/api/v1"
    CORS_ORIGINS: list[str] = Field(default_factory=list)

    DATABASE_URL: str = "postgresql+psycopg://postgres:postgres@127.0.0.1:5433/im"
    REDIS_URL: str = "redis://localhost:6379/0"

    JWT_SECRET: SecretStr = SecretStr("change-me-in-prod")
    JWT_ALGORITHM: str = "HS256"
    JWT_ACCESS_TTL_MIN: int = 60
    JWT_REFRESH_TTL_DAYS: int = 30

    OTP_TTL_MIN: int = 15
    OTP_MAX_ATTEMPTS: int = 5
    OTP_RATE_LIMIT_PER_EMAIL_SEC: int = 60
    OTP_RATE_LIMIT_PER_IP_HOUR: int = 10

    SMTP_HOST: str = "127.0.0.1"
    SMTP_PORT: int = 1025
    SMTP_USER: str = ""
    SMTP_PASSWORD: SecretStr = SecretStr("")
    SMTP_TLS: bool = False
    SMTP_FROM: str = "noreply@im.local"
    SMTP_FROM_NAME: str = "Important Memories"

    S3_ENDPOINT: str = "http://localhost:9000"
    S3_PUBLIC_URL: str = ""
    S3_REGION: str = "ru-central1"
    S3_BUCKET: str = "im-media"
    S3_ACCESS_KEY: str = "minioadmin"
    S3_SECRET_KEY: SecretStr = SecretStr("minioadmin")
    S3_PRESIGN_TTL_SEC: int = 600

    YOOKASSA_SHOP_ID: str = ""
    YOOKASSA_SECRET: SecretStr = SecretStr("")
    # Deprecated: YooKassa не подписывает webhook payload HMAC.
    # Оставлено для обратной совместимости с существующими .env файлами.
    # Защита webhook: nginx IP-whitelist (см. infra/nginx.conf).
    YOOKASSA_WEBHOOK_SECRET: SecretStr = SecretStr("deprecated-not-used")

    FCM_PROJECT_ID: str = ""
    FCM_CREDENTIALS_JSON: SecretStr = SecretStr("")

    SENTRY_DSN: str | None = None

    PUBLIC_API_BASE_URL: str = "http://localhost:8000"
    PUBLIC_PWA_BASE_URL: str = "https://192.168.1.109:5173"


@lru_cache
def get_settings() -> Settings:
    return Settings()


settings = get_settings()
