"""add event PIN + join_attempts audit + invite_tokens

Revision ID: b2c3d4e5f6a7
Revises: a1b2c3d4e5f6
Create Date: 2026-09-12 10:00:00.000000

Части:
1. events.entry_pin (String 6), events.pin_enabled (Bool, default False)
2. join_attempts — аудит попыток входа
3. invite_tokens — персональные приглашения в обход PIN и лимита событий/24ч
"""
from collections.abc import Sequence

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql


revision: str = "b2c3d4e5f6a7"
down_revision: str | None = "a1b2c3d4e5f6"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    # --- events: PIN fields ---
    op.add_column(
        "events",
        sa.Column("entry_pin", sa.String(length=6), nullable=True),
    )
    op.add_column(
        "events",
        sa.Column(
            "pin_enabled",
            sa.Boolean(),
            server_default=sa.text("false"),
            nullable=False,
        ),
    )

    # --- join_attempts ---
    # Enum создаётся через postgresql.ENUM(create_type=False) в колонке, а сам
    # тип — отдельным .create() до create_table. checkfirst=True не даст упасть
    # при повторном ране на существующем типе.
    outcome_enum = postgresql.ENUM(
        "ok",
        "bad_code",
        "bad_pin",
        "pin_required",
        "rate_limited",
        "event_closed",
        "guest_limit",
        "album_cap",
        name="join_attempt_outcome",
        create_type=False,
    )
    outcome_enum.create(op.get_bind(), checkfirst=True)

    op.create_table(
        "join_attempts",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column(
            "event_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("events.id", ondelete="SET NULL"),
            nullable=True,
        ),
        sa.Column("ip_hash", sa.String(length=64), nullable=True),
        sa.Column("fingerprint_hash", sa.String(length=64), nullable=True),
        sa.Column("short_code_tried", sa.String(length=16), nullable=False),
        sa.Column(
            "pin_tried",
            sa.Boolean(),
            server_default=sa.text("false"),
            nullable=False,
        ),
        sa.Column("outcome", outcome_enum, nullable=False),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
    )
    op.create_index(
        "ix_join_attempts_event_created", "join_attempts", ["event_id", "created_at"]
    )
    op.create_index(
        "ix_join_attempts_ip_created", "join_attempts", ["ip_hash", "created_at"]
    )
    op.create_index(
        "ix_join_attempts_fp_created",
        "join_attempts",
        ["fingerprint_hash", "created_at"],
    )

    # --- invite_tokens ---
    op.create_table(
        "invite_tokens",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column(
            "event_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("events.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("token", sa.String(length=64), nullable=False),
        sa.Column("display_name", sa.String(length=40), nullable=False),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
        sa.Column("used_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column(
            "used_by_guest_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("guests.id", ondelete="SET NULL"),
            nullable=True,
        ),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=True),
    )
    op.create_unique_constraint("uq_invite_tokens_token", "invite_tokens", ["token"])
    op.create_index("ix_invite_tokens_token", "invite_tokens", ["token"])
    op.create_index("ix_invite_tokens_event", "invite_tokens", ["event_id"])


def downgrade() -> None:
    op.drop_index("ix_invite_tokens_event", table_name="invite_tokens")
    op.drop_index("ix_invite_tokens_token", table_name="invite_tokens")
    op.drop_constraint("uq_invite_tokens_token", "invite_tokens", type_="unique")
    op.drop_table("invite_tokens")

    op.drop_index("ix_join_attempts_fp_created", table_name="join_attempts")
    op.drop_index("ix_join_attempts_ip_created", table_name="join_attempts")
    op.drop_index("ix_join_attempts_event_created", table_name="join_attempts")
    op.drop_table("join_attempts")

    postgresql.ENUM(name="join_attempt_outcome").drop(op.get_bind(), checkfirst=True)

    op.drop_column("events", "pin_enabled")
    op.drop_column("events", "entry_pin")
