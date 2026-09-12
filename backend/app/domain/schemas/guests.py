import html as html_mod
import re
from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, field_validator

from app.domain.schemas.events import EventSettingsOut


# Fingerprint из клиентов — hex/base16.
#   PWA (legacy): djb2 хеш (8 hex-символов) — оставили для backwards-compat действующих гостей.
#   Flutter: 16 random bytes → 32 hex.
#   Новый PWA будет использовать crypto.randomUUID (32 hex).
# Приняли: 8..64 hex-символов, только hex. Отсекает произвольные строки от бота
# ("aaaa", "junk"), но не ломает уже подключённых гостей.
_FINGERPRINT_RE = re.compile(r"^[a-fA-F0-9]{8,64}$")
# PIN — ровно 4 цифры. Строго numeric, чтобы не путать буквенные символы.
_PIN_RE = re.compile(r"^\d{4}$")


def _sanitize_name(v: str | None) -> str | None:
    """Escape HTML in user-supplied names to prevent XSS in album views."""
    if v is None:
        return None
    stripped = v.strip()
    if not stripped:
        return None
    return html_mod.escape(stripped, quote=True)


class EventPreviewOut(BaseModel):
    title: str
    frames_per_guest: int
    reveal_at: datetime | None
    start_at: datetime | None = None
    lut_preset: str
    status: str = "active"
    cover_url: str | None = None
    # true → клиент должен запросить PIN перед POST /sessions.
    # Не раскрывает сам PIN — только флаг, что второй фактор требуется.
    pin_required: bool = False


class GuestJoinIn(BaseModel):
    short_code: str = Field(min_length=4, max_length=16)
    # Если запрос с Bearer и юзер уже подключён к событию — name можно не передавать
    # (будет использован existing.name). Для нового invited гостя — fallback на user.display_name.
    # Для анонимного гостя — обязательно.
    name: str | None = Field(default=None, max_length=40)
    fingerprint: str = Field(min_length=8, max_length=64)
    # Опциональный PIN (4 цифры). Требуется только если event.pin_enabled=True.
    pin: str | None = Field(default=None, min_length=4, max_length=4)

    @field_validator("name")
    @classmethod
    def _sanitize(cls, v: str | None) -> str | None:
        return _sanitize_name(v)

    @field_validator("fingerprint")
    @classmethod
    def _validate_fingerprint(cls, v: str) -> str:
        if not _FINGERPRINT_RE.match(v):
            raise ValueError("fingerprint must be 32–64 hex characters")
        return v.lower()

    @field_validator("pin")
    @classmethod
    def _validate_pin(cls, v: str | None) -> str | None:
        if v is None:
            return None
        if not _PIN_RE.match(v):
            raise ValueError("pin must be exactly 4 digits")
        return v


class EventPinUpdateIn(BaseModel):
    """Управление PIN события. Три состояния:
    - enabled=True, pin="1234" — установить PIN
    - enabled=True, pin=None   — сгенерировать новый случайный PIN
    - enabled=False            — отключить PIN (pin в БД очищается)
    """
    enabled: bool
    pin: str | None = Field(default=None, min_length=4, max_length=4)

    @field_validator("pin")
    @classmethod
    def _validate_pin(cls, v: str | None) -> str | None:
        if v is None:
            return None
        if not _PIN_RE.match(v):
            raise ValueError("pin must be exactly 4 digits")
        return v


class EventPinOut(BaseModel):
    """Возвращается хосту после set/rotate. Гостям pin никогда не отдаём."""
    pin_enabled: bool
    entry_pin: str | None


class InviteCreateIn(BaseModel):
    """Хост создаёт персональное приглашение — «для Анны», «для Ивана»."""
    display_name: str = Field(min_length=1, max_length=40)
    # Дней жизни (None = без срока). Максимум 90.
    ttl_days: int | None = Field(default=None, ge=1, le=90)

    @field_validator("display_name")
    @classmethod
    def _sanitize(cls, v: str) -> str:
        clean = _sanitize_name(v)
        if not clean:
            raise ValueError("display_name required")
        return clean


class InviteTokenOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    token: str
    display_name: str
    created_at: datetime
    used_at: datetime | None = None
    expires_at: datetime | None = None
    # Готовая ссылка для шаринга.
    invite_url: str | None = None


class JoinStatsOut(BaseModel):
    """Агрегация JoinAttempt для хоста за последние 24 часа."""
    window_hours: int = 24
    total: int = 0
    ok: int = 0
    bad_code: int = 0
    bad_pin: int = 0
    pin_required: int = 0
    rate_limited: int = 0
    other: int = 0
    unique_ips: int = 0
    unique_fingerprints: int = 0
    # true → всплеск подозрительной активности (bad_pin+bad_code >= 20 за 1 час)
    suspicious: bool = False


class GuestNameUpdateIn(BaseModel):
    name: str = Field(min_length=1, max_length=40)

    @field_validator("name")
    @classmethod
    def _sanitize(cls, v: str) -> str:
        clean = _sanitize_name(v)
        if not clean:
            raise ValueError("Имя не может быть пустым")
        return clean


class GuestProfileUpdateIn(BaseModel):
    """Обновление публичного профиля гостя: имя, аватар, био.
    Все поля опциональные — можно менять по одному."""
    name: str | None = Field(default=None, max_length=40)
    avatar_key: str | None = Field(default=None, max_length=512)
    bio: str | None = Field(default=None, max_length=160)

    @field_validator("name")
    @classmethod
    def _sanitize_name_field(cls, v: str | None) -> str | None:
        return _sanitize_name(v)

    @field_validator("bio")
    @classmethod
    def _sanitize_bio(cls, v: str | None) -> str | None:
        if v is None:
            return None
        stripped = v.strip()
        return stripped or None


class GuestAvatarPresignIn(BaseModel):
    content_type: str = Field(default="image/jpeg", max_length=64)
    size_bytes: int = Field(gt=0, le=2 * 1024 * 1024)  # ≤ 2 MB


class GuestAvatarPresignOut(BaseModel):
    avatar_key: str
    upload_url: str
    expires_in: int


class GuestPublicProfileOut(BaseModel):
    id: UUID
    name: str
    avatar_url: str | None = None
    bio: str | None = None
    frames_count: int
    joined_at: datetime


class InvitedEventOut(BaseModel):
    id: UUID
    short_code: str
    title: str
    status: str
    start_at: datetime | None = None
    end_at: datetime
    cover_url: str | None = None
    my_frames_count: int
    total_frames: int


class GuestEventOut(BaseModel):
    id: UUID
    title: str
    status: str
    start_at: datetime | None = None
    end_at: datetime
    settings: EventSettingsOut


class GuestSessionOut(BaseModel):
    model_config = ConfigDict(from_attributes=False)

    guest_id: UUID
    guest_token: str
    name: str
    avatar_url: str | None = None
    bio: str | None = None
    event: GuestEventOut
    frames_used: int
    frames_remaining: int
