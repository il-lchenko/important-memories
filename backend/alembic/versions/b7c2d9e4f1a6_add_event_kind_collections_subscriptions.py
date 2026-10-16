"""add events.kind, collections, collection_items, subscriptions

Revision ID: b7c2d9e4f1a6
Revises: 9d4e2b7a1c3f
Create Date: 2026-10-16 22:00:00.000000

events.kind: 'event' (с гостями) или 'solo' (личный альбом). String, без PG ENUM.
collections / collection_items: мини-альбомы (ссылки на кадры, файлы не копируются).
subscriptions: подписка «Плюс» (включается флагом SUBSCRIPTION_ENABLED).
"""
from collections.abc import Sequence

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql


revision: str = "b7c2d9e4f1a6"
down_revision: str | None = "9d4e2b7a1c3f"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    # Платёж подписки не привязан к событию.
    op.alter_column("payments", "event_id", existing_type=postgresql.UUID(as_uuid=True), nullable=True)
    op.add_column("events", sa.Column("kind", sa.String(8), nullable=False, server_default="event"))
    op.create_index("ix_events_user_kind", "events", ["user_id", "kind"])

    op.create_table(
        "collections",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("user_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("title", sa.String(80), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
    )
    op.create_index("ix_collections_user", "collections", ["user_id"])

    op.create_table(
        "collection_items",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("collection_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("collections.id", ondelete="CASCADE"), nullable=False),
        sa.Column("frame_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("frames.id", ondelete="CASCADE"), nullable=False),
        sa.Column("position", sa.Integer, nullable=False, server_default="0"),
        sa.Column("added_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.UniqueConstraint("collection_id", "frame_id", name="uq_collection_items_collection_frame"),
    )
    op.create_index("ix_collection_items_frame", "collection_items", ["frame_id"])

    op.create_table(
        "subscriptions",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("user_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("status", sa.String(16), nullable=False, server_default="active"),
        sa.Column("period", sa.String(8), nullable=False, server_default="month"),
        sa.Column("payment_method_id", sa.String(128), nullable=True),
        sa.Column("current_period_start", sa.DateTime(timezone=True), nullable=False),
        sa.Column("current_period_end", sa.DateTime(timezone=True), nullable=False),
        sa.Column("cancel_at_period_end", sa.Boolean, nullable=False, server_default="false"),
        sa.Column("retry_count", sa.Integer, nullable=False, server_default="0"),
        sa.Column("next_retry_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
    )
    op.create_index("ix_subscriptions_user", "subscriptions", ["user_id"], unique=True)
    op.create_index("ix_subscriptions_current_period_end", "subscriptions", ["current_period_end"])


def downgrade() -> None:
    op.drop_index("ix_subscriptions_current_period_end", table_name="subscriptions")
    op.drop_index("ix_subscriptions_user", table_name="subscriptions")
    op.drop_table("subscriptions")
    op.drop_index("ix_collection_items_frame", table_name="collection_items")
    op.drop_table("collection_items")
    op.drop_index("ix_collections_user", table_name="collections")
    op.drop_table("collections")
    op.drop_index("ix_events_user_kind", table_name="events")
    op.drop_column("events", "kind")
    op.execute("DELETE FROM payments WHERE event_id IS NULL")
    op.alter_column("payments", "event_id", existing_type=postgresql.UUID(as_uuid=True), nullable=False)
