"""update enums: lut_preset values, event_type add party/graduation

Revision ID: b1c2d3e4f5a6
Revises: ebee75088b30
Create Date: 2026-05-22 12:00:00.000000

"""
from collections.abc import Sequence

from alembic import op


revision: str = "b1c2d3e4f5a6"
down_revision: str | None = "ebee75088b30"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    # --- lut_preset: rename old values + add original, ilford ---
    # PostgreSQL doesn't support renaming enum values directly.
    # Strategy: rename old type, create new type, migrate column, drop old.
    op.execute("ALTER TYPE lut_preset RENAME TO lut_preset_old")
    op.execute(
        "CREATE TYPE lut_preset AS ENUM "
        "('original', 'portra400', 'fuji400h', 'cinestill', 'ilford')"
    )
    op.execute("""
        ALTER TABLE event_settings
        ALTER COLUMN lut_preset TYPE lut_preset
        USING (
            CASE lut_preset::text
                WHEN 'portra'   THEN 'portra400'
                WHEN 'fuji'     THEN 'fuji400h'
                ELSE lut_preset::text
            END
        )::lut_preset
    """)
    op.execute("DROP TYPE lut_preset_old")

    # --- event_type: add party, graduation ---
    op.execute("ALTER TYPE event_type ADD VALUE IF NOT EXISTS 'party'")
    op.execute("ALTER TYPE event_type ADD VALUE IF NOT EXISTS 'graduation'")


def downgrade() -> None:
    # Revert lut_preset to original values
    op.execute("ALTER TYPE lut_preset RENAME TO lut_preset_old")
    op.execute(
        "CREATE TYPE lut_preset AS ENUM ('portra', 'fuji', 'cinestill')"
    )
    op.execute("""
        ALTER TABLE event_settings
        ALTER COLUMN lut_preset TYPE lut_preset
        USING (
            CASE lut_preset::text
                WHEN 'portra400' THEN 'portra'
                WHEN 'fuji400h'  THEN 'fuji'
                WHEN 'original'  THEN 'portra'
                WHEN 'ilford'    THEN 'portra'
                ELSE lut_preset::text
            END
        )::lut_preset
    """)
    op.execute("DROP TYPE lut_preset_old")
    # Note: PostgreSQL cannot remove values from an enum — party/graduation remain.
