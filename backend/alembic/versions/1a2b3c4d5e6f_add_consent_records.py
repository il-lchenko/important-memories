"""add consent_records table

Revision ID: 1a2b3c4d5e6f
Revises: b2c3d4e5f6a7
Create Date: 2026-09-19 12:00:00.000000

Аудит принятия юр. документов пользователем (Оферта / Политика /
Согласие на ПД / Правила контента) для доказывания получения согласия
по ст. 9 152-ФЗ (в редакции с 01.09.2025).
"""
from collections.abc import Sequence

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql


revision: str = "1a2b3c4d5e6f"
down_revision: str | None = "b2c3d4e5f6a7"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "consent_records",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("user_id", postgresql.UUID(as_uuid=True), nullable=True),
        sa.Column("guest_id", postgresql.UUID(as_uuid=True), nullable=True),
        sa.Column("fingerprint_hash", sa.String(length=64), nullable=True),
        sa.Column("doc_type", sa.String(length=32), nullable=False),
        sa.Column("doc_version", sa.String(length=16), nullable=False),
        sa.Column("ip_hash", sa.String(length=64), nullable=True),
        sa.Column("user_agent", sa.String(length=200), nullable=True),
        sa.Column(
            "accepted_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["guest_id"], ["guests.id"], ondelete="CASCADE"),
        sa.CheckConstraint(
            "user_id IS NOT NULL OR guest_id IS NOT NULL OR fingerprint_hash IS NOT NULL",
            name="ck_consent_records_subject_required",
        ),
    )
    op.create_index(
        "ix_consent_records_user_doc_version",
        "consent_records",
        ["user_id", "doc_type", "doc_version"],
    )
    op.create_index(
        "ix_consent_records_guest_doc_version",
        "consent_records",
        ["guest_id", "doc_type", "doc_version"],
    )
    op.create_index(
        "ix_consent_records_fp_doc_version",
        "consent_records",
        ["fingerprint_hash", "doc_type", "doc_version"],
    )


def downgrade() -> None:
    op.drop_index("ix_consent_records_fp_doc_version", table_name="consent_records")
    op.drop_index("ix_consent_records_guest_doc_version", table_name="consent_records")
    op.drop_index("ix_consent_records_user_doc_version", table_name="consent_records")
    op.drop_table("consent_records")
