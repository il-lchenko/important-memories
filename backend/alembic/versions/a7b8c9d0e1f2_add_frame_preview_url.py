"""add preview_url to frames (1600px quality preview for gallery)

Revision ID: a7b8c9d0e1f2
Revises: f6a7b8c9d0e1
Create Date: 2026-07-01 13:30:00.000000

"""
from collections.abc import Sequence

from alembic import op
import sqlalchemy as sa


revision: str = "a7b8c9d0e1f2"
down_revision: str | None = "f6a7b8c9d0e1"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column(
        "frames",
        sa.Column("preview_url", sa.String(length=1024), nullable=True),
    )


def downgrade() -> None:
    op.drop_column("frames", "preview_url")
