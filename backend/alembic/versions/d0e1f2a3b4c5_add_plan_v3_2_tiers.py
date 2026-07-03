"""add plan v3.2 discrete tiers (p75, p175, p200, p250, custom)

Adds the missing Plan enum values from business plan v3.2 pricing grid.
Existing UNLIMITED value is kept as legacy (treated as P250 in code).

Revision ID: d0e1f2a3b4c5
Revises: c9d0e1f2a3b4
Create Date: 2026-07-02 04:00:00.000000

"""
from collections.abc import Sequence

from alembic import op


revision: str = "d0e1f2a3b4c5"
down_revision: str | None = "c9d0e1f2a3b4"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


NEW_VALUES = ("p75", "p175", "p200", "p250", "custom")


def upgrade() -> None:
    # PostgreSQL: ALTER TYPE ... ADD VALUE — cannot run inside a transaction block
    # in older PG versions, but on 12+ it works fine. We use IF NOT EXISTS для идемпотентности.
    for value in NEW_VALUES:
        op.execute(f"ALTER TYPE plan ADD VALUE IF NOT EXISTS '{value}'")

    # Bump default frames_per_guest 24 → 30 for future rows.
    op.alter_column("event_settings", "frames_per_guest", server_default="30")


def downgrade() -> None:
    # PostgreSQL does not support removing enum values without recreating the type.
    # We only revert the default.
    op.alter_column("event_settings", "frames_per_guest", server_default="24")
