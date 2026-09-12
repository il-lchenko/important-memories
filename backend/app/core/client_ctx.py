"""Helpers для безопасного извлечения client-контекста из HTTP-запроса.

Ключевые правила:
- `X-Real-IP` доверяем ТОЛЬКО когда прямое TCP-подключение пришло с localhost
  (nginx на том же хосте). Иначе злоумышленник шлёт свой X-Real-IP и обнуляет
  rate-limit каждым запросом. Прод-nginx проксирует изнутри Docker network,
  поэтому request.client.host будет 127.0.0.1 или адрес bridge-сети.
- Fingerprint хешируем перед записью в БД: SHA-256(fp + salt). Так же для IP.
"""
import hashlib
from ipaddress import ip_address, ip_network

from fastapi import Request

from app.core.config import settings


# Сети, чьим X-Real-IP/X-Forwarded-For доверяем.
# Docker bridge (172.16/12), loopback (127/8, ::1), private (10.0/8) — nginx
# в контейнере попадает во внутренние сети, а не с интернета напрямую.
_TRUSTED_PROXY_NETS = [
    ip_network("127.0.0.0/8"),
    ip_network("::1/128"),
    ip_network("10.0.0.0/8"),
    ip_network("172.16.0.0/12"),
    ip_network("192.168.0.0/16"),
]


def _is_trusted_proxy(addr: str | None) -> bool:
    if not addr:
        return False
    try:
        a = ip_address(addr)
    except ValueError:
        return False
    return any(a in net for net in _TRUSTED_PROXY_NETS)


def client_ip(request: Request) -> str | None:
    """Возвращает истинный IP клиента.

    Если прямой peer — trusted proxy (nginx в docker), берём X-Real-IP.
    Иначе игнорируем header и возвращаем прямой peer — злоумышленник не сможет
    подсунуть свой IP через header напрямую в FastAPI.
    """
    peer = request.client.host if request.client else None
    if _is_trusted_proxy(peer):
        xr = request.headers.get("x-real-ip")
        if xr:
            candidate = xr.split(",")[0].strip()
            # Проверяем, что header содержит валидный IP (чтобы никто не подсунул
            # 5000-символовую строку).
            try:
                ip_address(candidate)
                return candidate
            except ValueError:
                pass
    return peer


def _sha256(value: str) -> str:
    salt = settings.ANTI_BRUTE_HASH_SALT.get_secret_value()
    return hashlib.sha256(f"{value}:{salt}".encode()).hexdigest()


def hash_ip(ip: str | None) -> str | None:
    """SHA-256(ip + salt) — 64 hex-символа. Не позволяет восстановить IP,
    но одинаковые IP дают одинаковый хеш → счётчик работает."""
    return _sha256(ip) if ip else None


def hash_fingerprint(fp: str | None) -> str | None:
    """То же для fingerprint. Приведён к lower-case."""
    return _sha256(fp.lower()) if fp else None
