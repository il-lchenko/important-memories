"""add notification anti-dup flags to events

Revision ID: c9d0e1f2a3b4
Revises: b8c9d0e1f2a3
Create Date: 2026-07-01 17:00:00.000000

"""
from collections.abc import Sequence

from alembic import op
import sqlalchemy as sa


revision: str = "c9d0e1f2a3b4"
down_revision: str | None = "b8c9d0e1f2a3"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    for col in ("notified_7d", "notified_3d", "notified_1d"):
        op.add_column(
            "events",
            sa.Column(col, sa.Boolean(), nullable=False, server_default=sa.false()),
        )


def downgrade() -> None:
    for col in ("notified_1d", "notified_3d", "notified_7d"):
        op.drop_column("events", col)
