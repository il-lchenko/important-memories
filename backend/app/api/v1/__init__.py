from fastapi import APIRouter

from app.api.v1 import (
    admin_promocodes,
    auth,
    collections,
    consent,
    devices,
    events,
    frames,
    guests,
    me,
    memories,
    payments,
    public,
    reports,
    subscription,
    users,
    webhooks,
)

api_router = APIRouter()
api_router.include_router(auth.router, prefix="/auth", tags=["auth"])
api_router.include_router(users.router, prefix="/users", tags=["users"])
api_router.include_router(me.router, prefix="/me", tags=["me"])
api_router.include_router(events.router, prefix="/events", tags=["events"])
api_router.include_router(payments.router, prefix="", tags=["payments"])
api_router.include_router(admin_promocodes.router, prefix="/admin", tags=["admin"])
api_router.include_router(guests.router, prefix="/guest", tags=["guest"])
api_router.include_router(frames.router, prefix="/guest/frames", tags=["frames"])
api_router.include_router(devices.router, prefix="/devices", tags=["devices"])
api_router.include_router(memories.router, prefix="/memories", tags=["memories"])
api_router.include_router(collections.router, prefix="/collections", tags=["collections"])
api_router.include_router(subscription.router, prefix="", tags=["subscription"])
api_router.include_router(reports.router, prefix="/reports", tags=["reports"])
api_router.include_router(webhooks.router, prefix="/webhooks", tags=["webhooks"])
api_router.include_router(public.router, prefix="/public", tags=["public"])
api_router.include_router(consent.router, prefix="", tags=["consent"])
