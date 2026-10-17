"""add collections.cover_key

Revision ID: d4e6f8a1b2c3
Revises: c8d3e5f2a7b9
Create Date: 2026-10-18 12:00:00.000000

Обложка мини-альбома: S3-ключ загруженного фото или копии выбранного кадра.
"""
from collections.abc import Sequence

from alembic import op
import sqlalchemy as sa


revision: str = "d4e6f8a1b2c3"
down_revision: str | None = "c8d3e5f2a7b9"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column("collections", sa.Column("cover_key", sa.String(512), nullable=True))


def downgrade() -> None:
    op.drop_column("collections", "cover_key")
