"""add event_settings.qr_style и title_font — оформление на сервере

Revision ID: 7c1e9a4f2d6b
Revises: b3c4d5e6f7a8
Create Date: 2026-10-15 18:00:00.000000

Пресет QR (classic|dark|warm|mono) и шрифт заголовка альбома
(playfair|fraunces|caveat|manrope) раньше жили только в SharedPreferences
телефона. Теперь хранятся в event_settings, чтобы PWA и гости видели то же.
String + валидация в Pydantic-схеме, без PG ENUM. NULL = значение по умолчанию.
"""
from collections.abc import Sequence

from alembic import op
import sqlalchemy as sa


revision: str = "7c1e9a4f2d6b"
down_revision: str | None = "b3c4d5e6f7a8"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column("event_settings", sa.Column("qr_style", sa.String(length=16), nullable=True))
    op.add_column("event_settings", sa.Column("title_font", sa.String(length=16), nullable=True))


def downgrade() -> None:
    op.drop_column("event_settings", "title_font")
    op.drop_column("event_settings", "qr_style")
