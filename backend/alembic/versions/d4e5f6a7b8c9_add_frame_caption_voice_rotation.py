"""add caption, voice, rotation to frames

Revision ID: d4e5f6a7b8c9
Revises: c3d4e5f6a7b8
Create Date: 2026-05-30 23:00:00.000000

"""
from collections.abc import Sequence

from alembic import op
import sqlalchemy as sa


revision: str = "d4e5f6a7b8c9"
down_revision: str | None = "c3d4e5f6a7b8"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column(
        "frames",
        sa.Column("caption", sa.String(length=120), nullable=True),
    )
    op.add_column(
        "frames",
        sa.Column("voice_s3_key", sa.String(length=1024), nullable=True),
    )
    op.add_column(
        "frames",
        sa.Column("voice_duration_ms", sa.Integer(), nullable=True),
    )
    op.add_column(
        "frames",
        sa.Column("voice_peaks", sa.JSON(), nullable=True),
    )
    op.add_column(
        "frames",
        sa.Column(
            "rotation",
            sa.Integer(),
            nullable=False,
            server_default="0",
        ),
    )
    op.create_check_constraint(
        "ck_frames_rotation_valid",
        "frames",
        "rotation IN (0, 90, 180, 270)",
    )


def downgrade() -> None:
    op.drop_constraint("ck_frames_rotation_valid", "frames", type_="check")
    op.drop_column("frames", "rotation")
    op.drop_column("frames", "voice_peaks")
    op.drop_column("frames", "voice_duration_ms")
    op.drop_column("frames", "voice_s3_key")
    op.drop_column("frames", "caption")
