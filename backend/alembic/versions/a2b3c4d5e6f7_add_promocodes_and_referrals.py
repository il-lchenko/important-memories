"""add promocodes, referrals, admin bypass — payments become nullable yookassa_id

Revision ID: a2b3c4d5e6f7
Revises: 4d5e6f7a8b9c
Create Date: 2026-09-28 12:00:00.000000

"""
import secrets
from collections.abc import Sequence

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql


revision: str = "a2b3c4d5e6f7"
down_revision: str | None = "4d5e6f7a8b9c"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


_pc_kind = postgresql.ENUM(
    "admin_bypass", "referral", "manual",
    name="promocode_kind",
    create_type=False,
)
_pc_disc = postgresql.ENUM(
    "percent", "fixed",
    name="promocode_discount_type",
    create_type=False,
)
_pc_appl = postgresql.ENUM(
    "all", "checkout", "extend", "upgrade",
    name="promocode_applies_to",
    create_type=False,
)


def _generate_ref_code() -> str:
    # Base32 без похожих символов — 6 знаков, ~1 млрд вариантов.
    alphabet = "23456789ABCDEFGHJKLMNPQRSTUVWXYZ"
    return "IM-" + "".join(secrets.choice(alphabet) for _ in range(6))


def upgrade() -> None:
    # 1. Enums — идемпотентный CREATE через DO $$ EXCEPTION $$ (PostgreSQL не поддерживает
    # CREATE TYPE IF NOT EXISTS напрямую).
    op.execute("""
        DO $$ BEGIN
            CREATE TYPE promocode_kind AS ENUM ('admin_bypass', 'referral', 'manual');
        EXCEPTION WHEN duplicate_object THEN NULL; END $$;
    """)
    op.execute("""
        DO $$ BEGIN
            CREATE TYPE promocode_discount_type AS ENUM ('percent', 'fixed');
        EXCEPTION WHEN duplicate_object THEN NULL; END $$;
    """)
    op.execute("""
        DO $$ BEGIN
            CREATE TYPE promocode_applies_to AS ENUM ('all', 'checkout', 'extend', 'upgrade');
        EXCEPTION WHEN duplicate_object THEN NULL; END $$;
    """)

    # 2. users: referral_code + invited_by_user_id.
    op.add_column("users", sa.Column("referral_code", sa.String(length=16), nullable=True))
    op.add_column(
        "users",
        sa.Column("invited_by_user_id", postgresql.UUID(as_uuid=True), nullable=True),
    )
    op.create_index("ix_users_referral_code", "users", ["referral_code"], unique=True)
    op.create_index("ix_users_invited_by_user_id", "users", ["invited_by_user_id"])
    op.create_foreign_key(
        "fk_users_invited_by",
        source_table="users",
        referent_table="users",
        local_cols=["invited_by_user_id"],
        remote_cols=["id"],
        ondelete="SET NULL",
    )

    # 3. Backfill referral_code для существующих юзеров.
    conn = op.get_bind()
    users = conn.execute(sa.text("SELECT id FROM users")).fetchall()
    seen: set[str] = set()
    for (user_id,) in users:
        for _ in range(10):
            code = _generate_ref_code()
            if code in seen:
                continue
            seen.add(code)
            try:
                conn.execute(
                    sa.text("UPDATE users SET referral_code = :c WHERE id = :id"),
                    {"c": code, "id": user_id},
                )
                break
            except Exception:
                seen.discard(code)
                continue

    # 4. promocodes.
    op.create_table(
        "promocodes",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("code", sa.String(length=32), nullable=False),
        sa.Column("kind", _pc_kind, nullable=False, server_default="manual"),
        sa.Column(
            "discount_type",
            _pc_disc,
            nullable=False,
            server_default="percent",
        ),
        sa.Column("discount_value", sa.Integer(), nullable=False),
        sa.Column("max_redemptions", sa.Integer(), nullable=True),
        sa.Column("redemptions_count", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column(
            "applies_to",
            _pc_appl,
            nullable=False,
            server_default="all",
        ),
        sa.Column("min_amount_kopecks", sa.BigInteger(), nullable=False, server_default="0"),
        sa.Column("single_use_per_user", sa.Boolean(), nullable=False, server_default=sa.text("true")),
        sa.Column("created_by_user_id", postgresql.UUID(as_uuid=True), nullable=True),
        sa.Column("owner_user_id", postgresql.UUID(as_uuid=True), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.ForeignKeyConstraint(["created_by_user_id"], ["users.id"], ondelete="SET NULL"),
        sa.ForeignKeyConstraint(["owner_user_id"], ["users.id"], ondelete="CASCADE"),
    )
    op.create_index("ix_promocodes_code", "promocodes", ["code"], unique=True)
    op.create_index("ix_promocodes_owner_user_id", "promocodes", ["owner_user_id"])
    op.create_index("ix_promocodes_owner_kind", "promocodes", ["owner_user_id", "kind"])

    # 5. promocode_redemptions.
    op.create_table(
        "promocode_redemptions",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("promocode_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("user_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("payment_id", postgresql.UUID(as_uuid=True), nullable=True),
        sa.Column("discount_applied_kopecks", sa.BigInteger(), nullable=False),
        sa.Column("redeemed_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.ForeignKeyConstraint(["promocode_id"], ["promocodes.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["payment_id"], ["payments.id"], ondelete="SET NULL"),
        sa.UniqueConstraint("promocode_id", "user_id", name="uq_promocode_user"),
    )
    op.create_index("ix_promocode_redemptions_payment", "promocode_redemptions", ["payment_id"])

    # 6. payments: сделать yookassa_id nullable (admin-bypass / 100% promo).
    op.alter_column("payments", "yookassa_id", existing_type=sa.String(length=64), nullable=True)
    op.add_column(
        "payments",
        sa.Column("original_amount_kopecks", sa.BigInteger(), nullable=True),
    )
    op.add_column(
        "payments",
        sa.Column("promocode_redemption_id", postgresql.UUID(as_uuid=True), nullable=True),
    )
    op.create_foreign_key(
        "fk_payments_promocode_redemption",
        source_table="payments",
        referent_table="promocode_redemptions",
        local_cols=["promocode_redemption_id"],
        remote_cols=["id"],
        ondelete="SET NULL",
    )


def downgrade() -> None:
    op.drop_constraint("fk_payments_promocode_redemption", "payments", type_="foreignkey")
    op.drop_column("payments", "promocode_redemption_id")
    op.drop_column("payments", "original_amount_kopecks")
    op.alter_column("payments", "yookassa_id", existing_type=sa.String(length=64), nullable=False)

    op.drop_index("ix_promocode_redemptions_payment", table_name="promocode_redemptions")
    op.drop_table("promocode_redemptions")

    op.drop_index("ix_promocodes_owner_kind", table_name="promocodes")
    op.drop_index("ix_promocodes_owner_user_id", table_name="promocodes")
    op.drop_index("ix_promocodes_code", table_name="promocodes")
    op.drop_table("promocodes")

    op.drop_constraint("fk_users_invited_by", "users", type_="foreignkey")
    op.drop_index("ix_users_invited_by_user_id", table_name="users")
    op.drop_index("ix_users_referral_code", table_name="users")
    op.drop_column("users", "invited_by_user_id")
    op.drop_column("users", "referral_code")

    _pc_appl.drop(op.get_bind(), checkfirst=True)
    _pc_disc.drop(op.get_bind(), checkfirst=True)
    _pc_kind.drop(op.get_bind(), checkfirst=True)
