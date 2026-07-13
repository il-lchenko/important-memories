"""add guest.avatar_key and guest.bio for public profiles

Revision ID: f2a3b4c5d6e7
Revises: e1f2a3b4c5d6
Create Date: 2026-07-10 15:00:00.000000

"""
from collections.abc import Sequence

from alembic import op
import sqlalchemy as sa


revision: str = "f2a3b4c5d6e7"
down_revision: str | None = "e1f2a3b4c5d6"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column("guests", sa.Column("avatar_key", sa.String(length=512), nullable=True))
    op.add_column("guests", sa.Column("bio", sa.String(length=160), nullable=True))


def downgrade() -> None:
    op.drop_column("guests", "bio")
    op.drop_column("guests", "avatar_key")
