"""add missing enum values: plan (p25, p100), event_type (travel, vacation, concert)

Revision ID: f6a7b8c9d0e1
Revises: e5f6a7b8c9d0
Create Date: 2026-06-26 12:00:00.000000

"""
from collections.abc import Sequence

from alembic import op


revision: str = "f6a7b8c9d0e1"
down_revision: str | None = "e5f6a7b8c9d0"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    # ALTER TYPE ... ADD VALUE IF NOT EXISTS — идемпотентно, безопасно повторно.
    # Требует PG 12+ (на проде Timeweb стоит 16).
    op.execute("ALTER TYPE plan ADD VALUE IF NOT EXISTS 'p25'")
    op.execute("ALTER TYPE plan ADD VALUE IF NOT EXISTS 'p100'")

    op.execute("ALTER TYPE event_type ADD VALUE IF NOT EXISTS 'travel'")
    op.execute("ALTER TYPE event_type ADD VALUE IF NOT EXISTS 'vacation'")
    op.execute("ALTER TYPE event_type ADD VALUE IF NOT EXISTS 'concert'")


def downgrade() -> None:
    # PostgreSQL не умеет удалять значения из enum без пересоздания типа.
    # Downgrade — no-op.
    pass
