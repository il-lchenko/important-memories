"""add user_id to guests (for invited registered users)

Revision ID: e5f6a7b8c9d0
Revises: d4e5f6a7b8c9
Create Date: 2026-05-30 23:30:00.000000

"""
from collections.abc import Sequence

from alembic import op
import sqlalchemy as sa


revision: str = "e5f6a7b8c9d0"
down_revision: str | None = "d4e5f6a7b8c9"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column(
        "guests",
        sa.Column("user_id", sa.dialects.postgresql.UUID(as_uuid=True), nullable=True),
    )
    op.create_foreign_key(
        "fk_guests_user_id",
        "guests",
        "users",
        ["user_id"],
        ["id"],
        ondelete="SET NULL",
    )
    op.create_index("ix_guests_user_id", "guests", ["user_id"])


def downgrade() -> None:
    op.drop_index("ix_guests_user_id", table_name="guests")
    op.drop_constraint("fk_guests_user_id", "guests", type_="foreignkey")
    op.drop_column("guests", "user_id")
