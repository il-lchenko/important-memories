"""add frames.note — длинная заметка/мысль к кадру

Revision ID: b3c4d5e6f7a8
Revises: a2b3c4d5e6f7
Create Date: 2026-10-15 03:00:00.000000

Заметка (до 2000 символов) — независимая от caption/voice. Отображается
отдельным блоком в FrameFullscreen / frame_detail. Nullable, default NULL.
Старые кадры остаются без заметок — UI показывает только блок если note
не NULL, либо кнопку «Добавить заметку» для автора.
"""
from collections.abc import Sequence

from alembic import op
import sqlalchemy as sa


revision: str = "b3c4d5e6f7a8"
down_revision: str | None = "a2b3c4d5e6f7"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column(
        "frames",
        sa.Column("note", sa.String(length=2000), nullable=True),
    )


def downgrade() -> None:
    op.drop_column("frames", "note")
