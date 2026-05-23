from uuid import UUID

from pydantic import BaseModel

from app.domain.models.enums import Plan


class CheckoutIn(BaseModel):
    plan: Plan


class CheckoutOut(BaseModel):
    payment_id: UUID
    yookassa_id: str
    confirmation_url: str
    amount_kopecks: int
    currency: str = "RUB"
