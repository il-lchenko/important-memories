"""add expires_at and extension_history to events

Revision ID: b8c9d0e1f2a3
Revises: a7b8c9d0e1f2
Create Date: 2026-07-01 16:00:00.000000

"""
from collections.abc import Sequence

from alembic import op
import sqlalchemy as sa


revision: str = "b8c9d0e1f2a3"
down_revision: str | None = "a7b8c9d0e1f2"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column(
        "events",
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=True),
    )
    op.add_column(
        "events",
        sa.Column(
            "extension_history",
            sa.JSON(),
            nullable=False,
            server_default="[]",
        ),
    )
    op.create_index("ix_events_expires_at", "events", ["expires_at"])


def downgrade() -> None:
    op.drop_index("ix_events_expires_at", table_name="events")
    op.drop_column("events", "extension_history")
    op.drop_column("events", "expires_at")
