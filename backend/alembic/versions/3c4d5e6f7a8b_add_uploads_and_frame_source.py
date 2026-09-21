"""add uploads_enabled + Frame.source + Frame.upload_hash

Revision ID: 3c4d5e6f7a8b
Revises: 2b3c4d5e6f7a
Create Date: 2026-09-21 12:00:00.000000

Фича «Загрузка фото из галереи»:
1. event_settings.uploads_enabled — Хост осознанно включает (default False)
2. frames.source — enum ('camera', 'upload'), default 'camera' (server_default)
3. frames.upload_hash — SHA-256 hex для дедупа gallery-uploads
4. partial unique index (event_id, upload_hash) WHERE upload_hash IS NOT NULL
   AND status != 'deleted' — защита от гонки при параллельных presign с
   одинаковым хешем.

См. project_upload_from_gallery.md и план bubbly-imagining-quokka.md.
"""
from collections.abc import Sequence

from alembic import op
import sqlalchemy as sa


revision: str = "3c4d5e6f7a8b"
down_revision: str | None = "2b3c4d5e6f7a"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    # 1. event_settings.uploads_enabled
    op.add_column(
        "event_settings",
        sa.Column(
            "uploads_enabled",
            sa.Boolean(),
            server_default=sa.text("false"),
            nullable=False,
        ),
    )

    # 2. frame_source enum
    op.execute("CREATE TYPE frame_source AS ENUM ('camera', 'upload')")

    # 3. frames.source
    op.add_column(
        "frames",
        sa.Column(
            "source",
            sa.Enum("camera", "upload", name="frame_source", create_type=False),
            server_default="camera",
            nullable=False,
        ),
    )

    # 4. frames.upload_hash
    op.add_column(
        "frames",
        sa.Column("upload_hash", sa.String(length=64), nullable=True),
    )

    # 5. partial unique index — дедуп в рамках события, только для не-удалённых
    op.execute(
        """
        CREATE UNIQUE INDEX ix_frames_event_upload_hash
        ON frames (event_id, upload_hash)
        WHERE upload_hash IS NOT NULL AND status != 'deleted'
        """
    )


def downgrade() -> None:
    op.execute("DROP INDEX IF EXISTS ix_frames_event_upload_hash")
    op.drop_column("frames", "upload_hash")
    op.drop_column("frames", "source")
    op.execute("DROP TYPE IF EXISTS frame_source")
    op.drop_column("event_settings", "uploads_enabled")
