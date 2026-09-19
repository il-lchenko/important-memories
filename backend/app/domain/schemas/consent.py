"""Схемы для эндпоинтов принятия юр. документов (Оферта / Политика /
Согласие на ПД / Правила контента)."""
from datetime import datetime
from typing import Literal
from uuid import UUID

from pydantic import BaseModel, Field


DocType = Literal["offer", "privacy", "consent", "content_rules"]


class ConsentAcceptIn(BaseModel):
    doc_type: DocType
    doc_version: str = Field(min_length=1, max_length=16, pattern=r"^\d+\.\d+(?:\.\d+)?$")


class GuestConsentAcceptIn(ConsentAcceptIn):
    """Гость принимает согласие ДО создания Guest-записи — передаёт
    fingerprint. Позднее, при join, fingerprint связывается с guest_id."""
    fingerprint: str = Field(min_length=8, max_length=128, pattern=r"^[a-fA-F0-9\-]{8,128}$")


class ConsentOut(BaseModel):
    id: UUID
    doc_type: DocType
    doc_version: str
    accepted_at: datetime
