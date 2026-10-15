"""add events.activated_at и events.storage_purged_at

Revision ID: 9d4e2b7a1c3f
Revises: 7c1e9a4f2d6b
Create Date: 2026-10-16 12:00:00.000000

activated_at — когда событие стало ACTIVE: по нему считается лимит
бесплатных альбомов в месяц (created_at не годится: черновик могли создать
в прошлом месяце, а удалённые черновики вообще не активировались).
storage_purged_at — когда файлы альбома удалены из S3 по сроку хранения
или после удаления события; повторно не чистим.
"""
from collections.abc import Sequence

from alembic import op
import sqlalchemy as sa


revision: str = "9d4e2b7a1c3f"
down_revision: str | None = "7c1e9a4f2d6b"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column("events", sa.Column("activated_at", sa.DateTime(timezone=True), nullable=True))
    op.add_column("events", sa.Column("storage_purged_at", sa.DateTime(timezone=True), nullable=True))
    op.create_index("ix_events_activated_at", "events", ["activated_at"])
    # Уже активированные события: точной даты нет, берём дату создания.
    op.execute(
        "UPDATE events SET activated_at = created_at "
        "WHERE status IN ('active', 'completed') AND activated_at IS NULL"
    )


def downgrade() -> None:
    op.drop_index("ix_events_activated_at", table_name="events")
    op.drop_column("events", "storage_purged_at")
    op.drop_column("events", "activated_at")
