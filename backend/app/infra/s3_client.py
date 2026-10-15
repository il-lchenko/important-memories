from functools import lru_cache

import boto3
from botocore.client import Config

from app.core.config import settings


@lru_cache
def get_s3_client():
    # request_checksum_calculation="when_required" — иначе botocore >=1.36 добавляет
    # x-amz-sdk-checksum-algorithm + Content-Encoding: aws-chunked ко всем put_object,
    # а не-AWS S3 (twcstorage.ru) отдаёт этот header обратно на GET, ломая рендер
    # картинок в браузере.
    return boto3.client(
        "s3",
        endpoint_url=settings.S3_ENDPOINT,
        aws_access_key_id=settings.S3_ACCESS_KEY,
        aws_secret_access_key=settings.S3_SECRET_KEY.get_secret_value(),
        region_name=settings.S3_REGION,
        config=Config(
            signature_version="s3v4",
            s3={"addressing_style": "path"},
            request_checksum_calculation="when_required",
            response_checksum_validation="when_required",
        ),
    )


def _to_public(url: str) -> str:
    if settings.S3_PUBLIC_URL:
        return url.replace(settings.S3_ENDPOINT, settings.S3_PUBLIC_URL, 1)
    return url


def presign_put(key: str, content_type: str, expires_in: int | None = None) -> str:
    expires = expires_in or settings.S3_PRESIGN_TTL_SEC
    url = get_s3_client().generate_presigned_url(
        "put_object",
        Params={
            "Bucket": settings.S3_BUCKET,
            "Key": key,
            "ContentType": content_type,
        },
        ExpiresIn=expires,
        HttpMethod="PUT",
    )
    return _to_public(url)


def presign_get(key: str, expires_in: int = 3600) -> str:
    url = get_s3_client().generate_presigned_url(
        "get_object",
        Params={"Bucket": settings.S3_BUCKET, "Key": key},
        ExpiresIn=expires_in,
    )
    return _to_public(url)


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


def delete_object(key: str) -> None:
    """Best-effort удаление объекта; отсутствующие ключи не считаются ошибкой."""
    try:
        get_s3_client().delete_object(Bucket=settings.S3_BUCKET, Key=key)
    except Exception:
        pass


def list_objects(prefix: str):
    """Все объекты с префиксом: [(key, last_modified)]. Постранично, без ограничений."""
    client = get_s3_client()
    token: str | None = None
    while True:
        kwargs = {"Bucket": settings.S3_BUCKET, "Prefix": prefix, "MaxKeys": 1000}
        if token:
            kwargs["ContinuationToken"] = token
        page = client.list_objects_v2(**kwargs)
        for obj in page.get("Contents", []):
            yield obj["Key"], obj["LastModified"]
        if not page.get("IsTruncated"):
            return
        token = page.get("NextContinuationToken")


def delete_keys(keys: list[str]) -> int:
    """Удаление по одному ключу: DeleteObjects на S3-совместимых хранилищах
    с botocore >=1.36 упирается в контрольные суммы, а API-запросы у Timeweb бесплатны."""
    client = get_s3_client()
    deleted = 0
    for key in keys:
        try:
            client.delete_object(Bucket=settings.S3_BUCKET, Key=key)
            deleted += 1
        except Exception:
            pass
    return deleted


def delete_prefix(prefix: str) -> int:
    return delete_keys([key for key, _ in list_objects(prefix)])
