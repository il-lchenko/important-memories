# Important Memories — Backend

FastAPI + SQLAlchemy 2 + PostgreSQL + Redis + ARQ.

## Запуск локально

```powershell
uv sync
copy .env.example .env
# поднять Postgres+Redis+MinIO+MailHog:
cd ..\infra
docker compose up -d
cd ..\backend
uv run alembic upgrade head
uv run python run.py    # НЕ "uvicorn ..." напрямую — см. ниже
```

Проверка:
- API health: `http://127.0.0.1:8000/health`
- Swagger UI: `http://127.0.0.1:8000/docs`
- MailHog (письма из dev-окружения): `http://127.0.0.1:8025`
- MinIO console: `http://127.0.0.1:9001` (minioadmin / minioadmin)

## Почему `run.py`, а не `uvicorn`

На Windows uvicorn принудительно ставит `WindowsProactorEventLoopPolicy`, с которым psycopg
несовместим. `run.py` сам конструирует selector loop и запускает `uvicorn.Server` внутри него.

## Структура

См. `analysis/tech-spec.md` §6.2.
