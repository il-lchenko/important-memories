import asyncio
import sys
from contextlib import asynccontextmanager

import sentry_sdk
from fastapi import FastAPI, Request

if sys.platform == "win32":
    asyncio.set_event_loop_policy(asyncio.WindowsSelectorEventLoopPolicy())
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from app.api.v1 import api_router
from app.core.config import settings
from app.core.errors import AppError
from app.core.logging import configure_logging, logger
from app.core.redis import close_redis
from app.infra.queue import close_pool


@asynccontextmanager
async def lifespan(_: FastAPI):
    configure_logging()
    if settings.SENTRY_DSN:
        sentry_sdk.init(
            dsn=settings.SENTRY_DSN,
            environment=settings.APP_ENV,
            traces_sample_rate=0.1,
        )
    logger.info("startup", env=settings.APP_ENV, version=settings.APP_VERSION)
    yield
    await close_pool()
    await close_redis()
    logger.info("shutdown")


app = FastAPI(
    title=settings.APP_NAME,
    version=settings.APP_VERSION,
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.CORS_ORIGINS or ["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.exception_handler(AppError)
async def app_error_handler(_: Request, exc: AppError) -> JSONResponse:
    return JSONResponse(
        status_code=exc.http_status,
        content={
            "error": {
                "code": exc.code,
                "message": exc.message,
                "details": exc.details,
            },
        },
    )


@app.get("/health", tags=["meta"])
async def health() -> dict[str, str]:
    return {"status": "ok", "env": settings.APP_ENV, "version": settings.APP_VERSION}


app.include_router(api_router, prefix=settings.API_V1_PREFIX)
