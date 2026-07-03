from datetime import datetime, timezone
from uuid import UUID, uuid4

from enum import Enum as _PyEnum

from sqlalchemy import (
    JSON,
    BigInteger,
    Boolean,
    CheckConstraint,
    DateTime,
    Enum,
    ForeignKey,
    Index,
    Integer,
    String,
    UniqueConstraint,
    func,
)


def _enum_col(enum_cls: type[_PyEnum], name: str) -> Enum:
    """SQLAlchemy Enum that stores `.value`, not `.name`."""
    return Enum(
        enum_cls,
        name=name,
        values_callable=lambda e: [m.value for m in e],
    )
from sqlalchemy.dialects.postgresql import UUID as PG_UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.db import Base
from app.domain.models.enums import (
    EventStatus,
    EventType,
    FrameStatus,
    LutPreset,
    PaymentStatus,
    PhotoFormat,
    Plan,
    Platform,
    ReportCategory,
    ReportStatus,
    RevealMode,
)


def _uuid_pk() -> Mapped[UUID]:
    return mapped_column(PG_UUID(as_uuid=True), primary_key=True, default=uuid4)


def _ts(default_now: bool = True, nullable: bool = False) -> Mapped[datetime]:
    return mapped_column(
        DateTime(timezone=True),
        server_default=func.now() if default_now else None,
        nullable=nullable,
    )


class User(Base):
    __tablename__ = "users"

    id: Mapped[UUID] = _uuid_pk()
    email: Mapped[str] = mapped_column(String(320), unique=True, index=True, nullable=False)
    phone: Mapped[str | None] = mapped_column(String(32), nullable=True)
    display_name: Mapped[str | None] = mapped_column(String(120), nullable=True)
    is_admin: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    created_at: Mapped[datetime] = _ts()
    last_login_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)

    events: Mapped[list["Event"]] = relationship(back_populates="owner")
    device_tokens: Mapped[list["DeviceToken"]] = relationship(back_populates="user")


class Event(Base):
    __tablename__ = "events"
    __table_args__ = (
        Index("ix_events_user_status", "user_id", "status"),
    )

    id: Mapped[UUID] = _uuid_pk()
    user_id: Mapped[UUID] = mapped_column(
        PG_UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), nullable=False
    )
    short_code: Mapped[str] = mapped_column(String(16), unique=True, nullable=False)
    title: Mapped[str] = mapped_column(String(80), nullable=False)
    start_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    end_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    event_type: Mapped[EventType] = mapped_column(
        _enum_col(EventType, "event_type"), nullable=False, default=EventType.OTHER
    )
    status: Mapped[EventStatus] = mapped_column(
        _enum_col(EventStatus, "event_status"), nullable=False, default=EventStatus.DRAFT
    )
    cover_url: Mapped[str | None] = mapped_column(String(1024), nullable=True)
    # Storage retention: when the album's photos will be deleted from S3.
    # Set automatically on activate() based on Plan; extendable via /events/{id}/extend.
    expires_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True, index=True
    )
    # Log of paid storage extensions: [{"added_days": 90, "price_kopecks": 49000, "paid_at": ISO}]
    extension_history: Mapped[list[dict]] = mapped_column(
        JSON, default=list, server_default="[]", nullable=False
    )
    # Anti-duplicate flags for expiry push notifications (see workers/notifications.py).
    notified_7d: Mapped[bool] = mapped_column(default=False, server_default="false", nullable=False)
    notified_3d: Mapped[bool] = mapped_column(default=False, server_default="false", nullable=False)
    notified_1d: Mapped[bool] = mapped_column(default=False, server_default="false", nullable=False)
    created_at: Mapped[datetime] = _ts()
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=lambda: datetime.now(timezone.utc),
        onupdate=lambda: datetime.now(timezone.utc),
        nullable=False,
    )

    owner: Mapped[User] = relationship(back_populates="events")
    settings: Mapped["EventSettings"] = relationship(
        back_populates="event", uselist=False, cascade="all, delete-orphan"
    )
    guests: Mapped[list["Guest"]] = relationship(back_populates="event", cascade="all, delete-orphan")
    frames: Mapped[list["Frame"]] = relationship(back_populates="event", cascade="all, delete-orphan")
    payments: Mapped[list["Payment"]] = relationship(back_populates="event")


class EventSettings(Base):
    __tablename__ = "event_settings"

    event_id: Mapped[UUID] = mapped_column(
        PG_UUID(as_uuid=True),
        ForeignKey("events.id", ondelete="CASCADE"),
        primary_key=True,
    )
    # Business plan v3.2: base 30 frames/guest, extended to 45 for +5₽/guest.
    frames_per_guest: Mapped[int] = mapped_column(Integer, default=30, nullable=False)
    max_guests: Mapped[int] = mapped_column(Integer, default=5, nullable=False)
    reveal_mode: Mapped[RevealMode] = mapped_column(
        _enum_col(RevealMode, "reveal_mode"), default=RevealMode.INSTANT, nullable=False
    )
    reveal_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    plan: Mapped[Plan] = mapped_column(
        _enum_col(Plan, "plan"), default=Plan.FREE, nullable=False
    )
    lut_preset: Mapped[LutPreset] = mapped_column(
        _enum_col(LutPreset, "lut_preset"), default=LutPreset.PORTRA400, nullable=False
    )
    sound_enabled: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)
    photo_format: Mapped[PhotoFormat] = mapped_column(
        _enum_col(PhotoFormat, "photo_format"), default=PhotoFormat.PORTRAIT_34, nullable=False
    )

    event: Mapped[Event] = relationship(back_populates="settings")


class Guest(Base):
    __tablename__ = "guests"
    __table_args__ = (
        UniqueConstraint("event_id", "fingerprint", name="uq_guest_event_fp"),
        Index("ix_guests_user_id", "user_id"),
    )

    id: Mapped[UUID] = _uuid_pk()
    event_id: Mapped[UUID] = mapped_column(
        PG_UUID(as_uuid=True), ForeignKey("events.id", ondelete="CASCADE"), nullable=False
    )
    # Если гость зарегистрирован — связан с User. Иначе NULL (анонимный гость).
    # Заполняется автоматически при regist­рации (backfill по fingerprint) или при join с Bearer.
    user_id: Mapped[UUID | None] = mapped_column(
        PG_UUID(as_uuid=True), ForeignKey("users.id", ondelete="SET NULL"), nullable=True
    )
    name: Mapped[str] = mapped_column(String(40), nullable=False)
    guest_token: Mapped[str] = mapped_column(String(64), unique=True, nullable=False)
    fingerprint: Mapped[str] = mapped_column(String(128), nullable=False)
    joined_at: Mapped[datetime] = _ts()
    frames_used: Mapped[int] = mapped_column(Integer, default=0, nullable=False)

    event: Mapped[Event] = relationship(back_populates="guests")
    frames: Mapped[list["Frame"]] = relationship(back_populates="guest")


class Frame(Base):
    __tablename__ = "frames"
    __table_args__ = (
        Index("ix_frames_event_captured", "event_id", "captured_at"),
        Index("ix_frames_guest_status", "guest_id", "status"),
        CheckConstraint("rotation IN (0, 90, 180, 270)", name="ck_frames_rotation_valid"),
    )

    id: Mapped[UUID] = _uuid_pk()
    event_id: Mapped[UUID] = mapped_column(
        PG_UUID(as_uuid=True), ForeignKey("events.id", ondelete="CASCADE"), nullable=False
    )
    guest_id: Mapped[UUID] = mapped_column(
        PG_UUID(as_uuid=True), ForeignKey("guests.id", ondelete="CASCADE"), nullable=False
    )
    s3_key: Mapped[str] = mapped_column(String(512), nullable=False)
    thumbnail_url: Mapped[str | None] = mapped_column(String(1024), nullable=True)
    preview_url: Mapped[str | None] = mapped_column(String(1024), nullable=True)
    size_bytes: Mapped[int] = mapped_column(BigInteger, default=0, nullable=False)
    width: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    height: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    status: Mapped[FrameStatus] = mapped_column(
        _enum_col(FrameStatus, "frame_status"), default=FrameStatus.PENDING, nullable=False
    )
    captured_at: Mapped[datetime] = _ts()
    uploaded_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    deleted_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)

    caption: Mapped[str | None] = mapped_column(String(120), nullable=True)
    voice_s3_key: Mapped[str | None] = mapped_column(String(1024), nullable=True)
    voice_duration_ms: Mapped[int | None] = mapped_column(Integer, nullable=True)
    voice_peaks: Mapped[list[float] | None] = mapped_column(JSON, nullable=True)
    rotation: Mapped[int] = mapped_column(Integer, default=0, server_default="0", nullable=False)

    event: Mapped[Event] = relationship(back_populates="frames")
    guest: Mapped[Guest] = relationship(back_populates="frames")


class Payment(Base):
    __tablename__ = "payments"

    id: Mapped[UUID] = _uuid_pk()
    event_id: Mapped[UUID] = mapped_column(
        PG_UUID(as_uuid=True), ForeignKey("events.id", ondelete="CASCADE"), nullable=False
    )
    user_id: Mapped[UUID] = mapped_column(
        PG_UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), nullable=False
    )
    yookassa_id: Mapped[str] = mapped_column(String(64), unique=True, nullable=False)
    amount_kopecks: Mapped[int] = mapped_column(BigInteger, nullable=False)
    status: Mapped[PaymentStatus] = mapped_column(
        _enum_col(PaymentStatus, "payment_status"), default=PaymentStatus.PENDING, nullable=False
    )
    idempotency_key: Mapped[str] = mapped_column(String(64), unique=True, nullable=False)
    meta: Mapped[dict] = mapped_column(JSON, default=dict, nullable=False)
    created_at: Mapped[datetime] = _ts()
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=lambda: datetime.now(timezone.utc),
        onupdate=lambda: datetime.now(timezone.utc),
        nullable=False,
    )

    event: Mapped[Event] = relationship(back_populates="payments")


class DeviceToken(Base):
    __tablename__ = "device_tokens"

    id: Mapped[UUID] = _uuid_pk()
    user_id: Mapped[UUID] = mapped_column(
        PG_UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), nullable=False
    )
    platform: Mapped[Platform] = mapped_column(_enum_col(Platform, "platform"), nullable=False)
    token: Mapped[str] = mapped_column(String(512), unique=True, nullable=False)
    registered_at: Mapped[datetime] = _ts()
    last_used_at: Mapped[datetime] = _ts()

    user: Mapped[User] = relationship(back_populates="device_tokens")


class EmailCode(Base):
    __tablename__ = "email_codes"
    __table_args__ = (
        Index("ix_email_codes_lookup", "email", "consumed", "expires_at"),
    )

    id: Mapped[UUID] = _uuid_pk()
    email: Mapped[str] = mapped_column(String(320), nullable=False)
    code_hash: Mapped[str] = mapped_column(String(128), nullable=False)
    created_at: Mapped[datetime] = _ts()
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    attempts: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    consumed: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)


class Report(Base):
    __tablename__ = "reports"

    id: Mapped[UUID] = _uuid_pk()
    frame_id: Mapped[UUID | None] = mapped_column(
        PG_UUID(as_uuid=True), ForeignKey("frames.id", ondelete="SET NULL"), nullable=True
    )
    event_id: Mapped[UUID | None] = mapped_column(
        PG_UUID(as_uuid=True), ForeignKey("events.id", ondelete="SET NULL"), nullable=True
    )
    reporter_user_id: Mapped[UUID | None] = mapped_column(
        PG_UUID(as_uuid=True), ForeignKey("users.id", ondelete="SET NULL"), nullable=True
    )
    reporter_guest_id: Mapped[UUID | None] = mapped_column(
        PG_UUID(as_uuid=True), ForeignKey("guests.id", ondelete="SET NULL"), nullable=True
    )
    category: Mapped[ReportCategory] = mapped_column(
        _enum_col(ReportCategory, "report_category"), nullable=False
    )
    note: Mapped[str | None] = mapped_column(String(2000), nullable=True)
    status: Mapped[ReportStatus] = mapped_column(
        _enum_col(ReportStatus, "report_status"), default=ReportStatus.OPEN, nullable=False
    )
    created_at: Mapped[datetime] = _ts()


class AuditLog(Base):
    __tablename__ = "audit_log"

    id: Mapped[UUID] = _uuid_pk()
    user_id: Mapped[UUID | None] = mapped_column(PG_UUID(as_uuid=True), nullable=True)
    action: Mapped[str] = mapped_column(String(120), nullable=False, index=True)
    resource_id: Mapped[UUID | None] = mapped_column(PG_UUID(as_uuid=True), nullable=True)
    resource_type: Mapped[str | None] = mapped_column(String(64), nullable=True)
    payload: Mapped[dict] = mapped_column(JSON, default=dict, nullable=False)
    ip_address: Mapped[str | None] = mapped_column(String(64), nullable=True)
    created_at: Mapped[datetime] = _ts()
