"""add event.public_share_token for read-only share links

Revision ID: e1f2a3b4c5d6
Revises: d0e1f2a3b4c5
Create Date: 2026-07-09 12:00:00.000000

"""
from collections.abc import Sequence

from alembic import op
import sqlalchemy as sa


revision: str = "e1f2a3b4c5d6"
down_revision: str | None = "d0e1f2a3b4c5"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column(
        "events",
        sa.Column("public_share_token", sa.String(length=64), nullable=True),
    )
    op.create_unique_constraint(
        "uq_events_public_share_token", "events", ["public_share_token"]
    )
    op.create_index(
        "ix_events_public_share_token", "events", ["public_share_token"]
    )


def downgrade() -> None:
    op.drop_index("ix_events_public_share_token", table_name="events")
    op.drop_constraint("uq_events_public_share_token", "events", type_="unique")
    op.drop_column("events", "public_share_token")
