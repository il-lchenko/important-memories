from fastapi import APIRouter

from app.api.v1 import auth, devices, events, frames, guests, memories, payments, public, reports, users, webhooks

api_router = APIRouter()
api_router.include_router(auth.router, prefix="/auth", tags=["auth"])
api_router.include_router(users.router, prefix="/users", tags=["users"])
api_router.include_router(events.router, prefix="/events", tags=["events"])
api_router.include_router(payments.router, prefix="", tags=["payments"])
api_router.include_router(guests.router, prefix="/guest", tags=["guest"])
api_router.include_router(frames.router, prefix="/guest/frames", tags=["frames"])
api_router.include_router(devices.router, prefix="/devices", tags=["devices"])
api_router.include_router(memories.router, prefix="/memories", tags=["memories"])
api_router.include_router(reports.router, prefix="/reports", tags=["reports"])
api_router.include_router(webhooks.router, prefix="/webhooks", tags=["webhooks"])
api_router.include_router(public.router, prefix="/public", tags=["public"])
