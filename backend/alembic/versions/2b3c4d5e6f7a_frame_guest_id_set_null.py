"""frame.guest_id: CASCADE -> SET NULL, nullable=True

Revision ID: 2b3c4d5e6f7a
Revises: 1a2b3c4d5e6f
Create Date: 2026-09-20 15:00:00.000000

Право Гостя на удаление ПД (ст. 21 152-ФЗ) требует, чтобы после отзыва
согласия обработка ПД Гостя прекращалась, но при этом медиафайлы могут
оставаться в альбоме на основании законных интересов участников
(privacy v2.2 §10). Реализуется обезличиванием: Frame.guest_id → NULL
вместо каскадного удаления фрейма.
"""
from collections.abc import Sequence

from alembic import op


revision: str = "2b3c4d5e6f7a"
down_revision: str | None = "1a2b3c4d5e6f"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.alter_column("frames", "guest_id", nullable=True)
    op.drop_constraint("frames_guest_id_fkey", "frames", type_="foreignkey")
    op.create_foreign_key(
        "frames_guest_id_fkey",
        "frames",
        "guests",
        ["guest_id"],
        ["id"],
        ondelete="SET NULL",
    )


def downgrade() -> None:
    op.drop_constraint("frames_guest_id_fkey", "frames", type_="foreignkey")
    op.create_foreign_key(
        "frames_guest_id_fkey",
        "frames",
        "guests",
        ["guest_id"],
        ["id"],
        ondelete="CASCADE",
    )
    op.alter_column("frames", "guest_id", nullable=False)
