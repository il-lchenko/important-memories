from typing import Any


class AppError(Exception):
    code: str = "INTERNAL_ERROR"
    http_status: int = 500
    message: str = "Internal error"

    def __init__(self, message: str | None = None, details: dict[str, Any] | None = None):
        self.message = message or self.message
        self.details = details or {}
        super().__init__(self.message)


class AuthError(AppError):
    code = "UNAUTHORIZED"
    http_status = 401
    message = "Authentication required"


class PermissionDeniedError(AppError):
    code = "FORBIDDEN"
    http_status = 403
    message = "Forbidden"


class NotFoundError(AppError):
    code = "NOT_FOUND"
    http_status = 404
    message = "Resource not found"


class ConflictError(AppError):
    code = "CONFLICT"
    http_status = 409
    message = "Conflict"


class InvalidCodeError(AppError):
    code = "INVALID_CODE"
    http_status = 400
    message = "Неверный код"


class RateLimitError(AppError):
    code = "RATE_LIMITED"
    http_status = 429
    message = "Too many requests"


class PinRequiredError(AppError):
    """Клиент должен прислать PIN. Отдельный код, чтобы фронт мог отличить
    от общего 400 и открыть PIN-экран."""
    code = "PIN_REQUIRED"
    http_status = 400
    message = "PIN required"


class BadPinError(AppError):
    """Клиент прислал неверный PIN. Отдельный код, чтобы фронт мог показать
    красную ошибку под полем без выхода на код-экран."""
    code = "BAD_PIN"
    http_status = 400
    message = "Неверный PIN"


class AlbumCapError(AppError):
    """Fingerprint исчерпал лимит новых альбомов за 24ч."""
    code = "ALBUM_CAP"
    http_status = 429
    message = "Слишком много новых альбомов за сутки"


class ExternalServiceError(AppError):
    code = "EXTERNAL_SERVICE_ERROR"
    http_status = 502
    message = "External service failure"
