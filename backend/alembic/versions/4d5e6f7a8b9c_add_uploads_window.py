"""add event_settings.uploads_window_ends_at

Revision ID: 4d5e6f7a8b9c
Revises: 3c4d5e6f7a8b
Create Date: 2026-09-25 18:00:00.000000

Пост-event окно для gallery-uploads. После завершения события (COMPLETED)
кнопка «Из галереи» у гостей скрыта. Хост в настройках альбома может явно
открыть окно на 2ч / 24ч / 7 дней — на этот срок uploads_window_ends_at
устанавливается в now()+X, и гости снова могут заливать файлы (только из
галереи; камера уже недоступна). NULL — окно закрыто (default для новых и
всех существующих событий).
"""
from collections.abc import Sequence

from alembic import op
import sqlalchemy as sa


revision: str = "4d5e6f7a8b9c"
down_revision: str | None = "3c4d5e6f7a8b"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column(
        "event_settings",
        sa.Column(
            "uploads_window_ends_at",
            sa.DateTime(timezone=True),
            nullable=True,
        ),
    )


def downgrade() -> None:
    op.drop_column("event_settings", "uploads_window_ends_at")
