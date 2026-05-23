from functools import lru_cache

import boto3
from botocore.client import Config

from app.core.config import settings


@lru_cache
def get_s3_client():
    return boto3.client(
        "s3",
        endpoint_url=settings.S3_ENDPOINT,
        aws_access_key_id=settings.S3_ACCESS_KEY,
        aws_secret_access_key=settings.S3_SECRET_KEY.get_secret_value(),
        region_name=settings.S3_REGION,
        config=Config(signature_version="s3v4", s3={"addressing_style": "path"}),
    )


def presign_put(key: str, content_type: str, expires_in: int | None = None) -> str:
    expires = expires_in or settings.S3_PRESIGN_TTL_SEC
    return get_s3_client().generate_presigned_url(
        "put_object",
        Params={
            "Bucket": settings.S3_BUCKET,
            "Key": key,
            "ContentType": content_type,
        },
        ExpiresIn=expires,
        HttpMethod="PUT",
    )


def presign_get(key: str, expires_in: int = 3600) -> str:
    return get_s3_client().generate_presigned_url(
        "get_object",
        Params={"Bucket": settings.S3_BUCKET, "Key": key},
        ExpiresIn=expires_in,
    )


def download_bytes(key: str) -> bytes:
    response = get_s3_client().get_object(Bucket=settings.S3_BUCKET, Key=key)
    return response["Body"].read()


def upload_bytes(key: str, data: bytes, content_type: str) -> None:
    get_s3_client().put_object(
        Bucket=settings.S3_BUCKET,
        Key=key,
        Body=data,
        ContentType=content_type,
    )
