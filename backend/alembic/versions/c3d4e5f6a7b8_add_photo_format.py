"""add photo_format to event_settings

Revision ID: c3d4e5f6a7b8
Revises: b1c2d3e4f5a6
Create Date: 2026-05-22 18:00:00.000000

"""
from collections.abc import Sequence

from alembic import op
import sqlalchemy as sa


revision: str = "c3d4e5f6a7b8"
down_revision: str | None = "b1c2d3e4f5a6"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.execute("CREATE TYPE photo_format AS ENUM ('portrait_34', 'landscape_43')")
    op.add_column(
        "event_settings",
        sa.Column(
            "photo_format",
            sa.Enum("portrait_34", "landscape_43", name="photo_format"),
            nullable=False,
            server_default="portrait_34",
        ),
    )


def downgrade() -> None:
    op.drop_column("event_settings", "photo_format")
    op.execute("DROP TYPE photo_format")
