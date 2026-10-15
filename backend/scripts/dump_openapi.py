"""Выгружает OpenAPI-схему для типов PWA.

Запуск из backend/: uv run python scripts/dump_openapi.py [путь]
По умолчанию пишет в ../guest-pwa/src/api/openapi.json.
"""
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from app.main import app  # noqa: E402

DEFAULT_OUT = Path(__file__).resolve().parents[2] / "guest-pwa" / "src" / "api" / "openapi.json"


def main() -> None:
    out = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_OUT
    out.parent.mkdir(parents=True, exist_ok=True)
    schema = app.openapi()
    with out.open("w", encoding="utf-8", newline="\n") as f:
        f.write(json.dumps(schema, ensure_ascii=False, indent=2) + "\n")
    print(f"OpenAPI: {len(schema.get('paths', {}))} paths -> {out}")


if __name__ == "__main__":
    main()
