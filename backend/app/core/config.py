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

    # Email через SMTP.bz (РФ-резидент, без трансграничной передачи ПД).
    # Приоритет провайдеров: SMTPBZ_API_KEY → UNISENDER_API_KEY → local SMTP_HOST.
    # Free tier: 15 000 писем/мес, 500/день, любые домены получателей.
    SMTPBZ_API_KEY: SecretStr = SecretStr("")
    SMTPBZ_FROM_EMAIL: str = "no-reply@impomento.pro"
    SMTPBZ_FROM_NAME: str = "ImpoMento"
    SMTPBZ_REPLY_TO: str = "support@impomento.pro"

    # Deprecated fallback: Unisender Go free tier не разрешает внешние домены получателей.
    UNISENDER_API_KEY: SecretStr = SecretStr("")
    UNISENDER_FROM_EMAIL: str = "no-reply@impomento.pro"
    UNISENDER_FROM_NAME: str = "ImpoMento"
    UNISENDER_REPLY_TO: str = "support@impomento.pro"

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
    S3_PRESIGN_TTL_SEC: int = 3600

    YOOKASSA_SHOP_ID: str = ""
    YOOKASSA_SECRET: SecretStr = SecretStr("")
    # Deprecated: YooKassa не подписывает webhook payload HMAC.
    # Оставлено для обратной совместимости с существующими .env файлами.
    # Защита webhook: nginx IP-whitelist (см. infra/nginx.conf).
    YOOKASSA_WEBHOOK_SECRET: SecretStr = SecretStr("deprecated-not-used")

    # Бесплатный тариф. None = без лимита.
    # FREE_ACTIVE_EVENTS — одновременно живых бесплатных альбомов (удаление освобождает место).
    # FREE_EVENTS_PER_MONTH — всего бесплатных активаций за календарный месяц,
    # чтобы «удалил — создал новый» не превращался в бесконечный бесплатный тариф.
    FREE_ACTIVE_EVENTS: int | None = 2
    FREE_EVENTS_PER_MONTH: int | None = 4
    # Новые цены (продление по числу гостей, 45 кадров, 250+, хранение 250+)
    # действуют для покупок с этой даты: оферта требует уведомить за 14 дней.
    PRICING_V2_FROM: str = "2026-11-01T00:00:00+03:00"
    # Очистка хранилища: файлы альбомов, у которых срок истёк, удаляются не раньше
    # этой даты, чтобы старые альбомы не пропали в день выкладки.
    STORAGE_PURGE_NOT_BEFORE: str = "2026-11-16T00:00:00+03:00"
    # Альбомы, созданные ДО этого момента, очистка не трогает никогда (они созданы
    # владельцем и знакомыми до введения сроков хранения). Альбомы админов
    # не удаляются независимо от даты создания.
    PURGE_PROTECT_CREATED_BEFORE: str = "2026-10-16T16:16:00+00:00"
    # Подписка «Плюс». Пока SUBSCRIPTION_ENABLED=false, платных ограничений по подписке нет:
    # действуют бесплатные лимиты, а доп. оформление доступно всем.
    SUBSCRIPTION_ENABLED: bool = False
    SUB_PRICE_MONTH_KOPECKS: int = 22900
    SUB_PRICE_YEAR_KOPECKS: int = 219000
    # События на 5 гостей по подписке.
    PLUS_FREE_ACTIVE_EVENTS: int = 3
    PLUS_FREE_EVENTS_PER_MONTH: int = 6
    # Соло-альбомы: кадров за календарный месяц, кадров в хранилище одновременно, срок хранения.
    SOLO_FREE_FRAMES_PER_MONTH: int = 150
    SOLO_FREE_STORED_FRAMES: int = 300
    SOLO_FREE_RETENTION_DAYS: int = 30
    SOLO_PLUS_FRAMES_PER_MONTH: int = 500
    SOLO_PLUS_STORED_FRAMES: int = 2000
    SOLO_PLUS_RETENTION_DAYS: int = 365
    # Мини-альбомы (подборки): число подборок (None у подписчиков) и кадров в подборке.
    MINI_FREE_ALBUMS: int = 3
    MINI_FREE_FRAMES_PER_ALBUM: int = 30
    MINI_PLUS_FRAMES_PER_ALBUM: int = 100

    FCM_PROJECT_ID: str = ""
    FCM_CREDENTIALS_JSON: SecretStr = SecretStr("")

    SENTRY_DSN: str | None = None

    PUBLIC_API_BASE_URL: str = "http://localhost:8000"
    PUBLIC_PWA_BASE_URL: str = "https://192.168.1.109:5173"

    # Соль для хеширования IP и fingerprint в join_attempts — не PII после хеширования,
    # но позволяет отличать разных нарушителей. Утечка соли не критична (кроме перебора
    # IP-адресов из /24 подсети).
    ANTI_BRUTE_HASH_SALT: SecretStr = SecretStr(
        "change-me-in-prod-anti-brute-salt-6f2b1e9c"
    )


@lru_cache
def get_settings() -> Settings:
    return Settings()


settings = get_settings()
