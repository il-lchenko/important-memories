"""add collections.public_share_token

Revision ID: c8d3e5f2a7b9
Revises: b7c2d9e4f1a6
Create Date: 2026-10-17 18:00:00.000000

Открытая ссылка на мини-альбом (подборку). Отдаются только кадры из собственных
событий владельца и снятые им самим кадры.
"""
from collections.abc import Sequence

from alembic import op
import sqlalchemy as sa


revision: str = "c8d3e5f2a7b9"
down_revision: str | None = "b7c2d9e4f1a6"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column("collections", sa.Column("public_share_token", sa.String(64), nullable=True))
    op.create_index("ix_collections_public_share_token", "collections", ["public_share_token"], unique=True)


def downgrade() -> None:
    op.drop_index("ix_collections_public_share_token", table_name="collections")
    op.drop_column("collections", "public_share_token")
