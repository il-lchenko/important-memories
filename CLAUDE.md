# Important Memories — CLAUDE.md

## Обязательно прочитай перед началом работы

Это стартап-проект, который ведёт один человек (Илья, Москва). Все ответы и пояснения — ТОЛЬКО на русском языке. Код и commit messages могут быть на английском.

Перед началом работы прочитай `memory/MEMORY.md` и последний session log — там полный контекст предыдущей сессии.

---

## Что за проект

**Important Memories** — мобильное приложение "одноразовая камера" для свадеб и мероприятий (аналог once.film / POV).

**Флоу:** Хост создаёт событие → получает QR-код → гости сканируют QR → делают фото через PWA → хост открывает альбом → все смотрят фото.

**Продакшн:** https://impomento.pro (VPS Timeweb Cloud, Docker)

---

## Структура проекта

```
host-app/       Flutter 3.27.1 — приложение для организатора (APK)
guest-pwa/      React 19 + Vite — PWA для гостей (сканируют QR в браузере)
backend/        FastAPI + SQLAlchemy 2 async + ARQ workers
infra/          Docker Compose, nginx config
```

---

## Стек технологий

**Flutter (host-app):**
- flutter_riverpod ^2.6.1 + riverpod_annotation (code gen)
- go_router ^14.6.2, dio ^5.7.0, flutter_secure_storage
- После изменений провайдеров: `dart run build_runner build --delete-conflicting-outputs`

**React PWA (guest-pwa):**
- React 19 + Vite + TypeScript + Tailwind CSS v4
- НЕТ tailwind.config.js — только `@tailwindcss/vite` plugin
- Build: `npm run build` → `dist/`

**Backend:**
- FastAPI, SQLAlchemy 2 async, ARQ workers
- Порт 8000, API: `/api/v1/...`

---

## Как запускать локально

```bash
# Backend
cd backend && uvicorn app.main:app --reload

# Guest PWA
cd guest-pwa && npm run dev   # Vite proxy → 127.0.0.1:8000

# Flutter (web)
cd host-app && flutter run -d web-server --web-renderer html --web-port 8080

# Flutter (Android APK)
cd host-app && flutter build apk --dart-define=API_URL=http://10.0.2.2:8000
```

**Деплой на VPS** (VPS_IP = `217.149.29.227`):
```bash
# PWA
cd guest-pwa && npm run build
scp -o StrictHostKeyChecking=no -r dist/. root@217.149.29.227:/opt/im/guest-pwa/dist/

# Backend (ВАЖНО: docker cp, не просто restart — код внутри образа, не volume)
# КРИТИЧНО: используй "backend/app/" → "/opt/im/backend/app/" с trailing slash В ОБОИХ концах
# ИЛИ "backend/app/." → "/opt/im/backend/app/" — иначе создаст /opt/im/backend/app/app/
scp -o StrictHostKeyChecking=no -r backend/app/. root@217.149.29.227:/opt/im/backend/app/
ssh -o StrictHostKeyChecking=no impomento "/opt/im/deploy-backend.sh"

# Если добавили миграцию Alembic:
scp -o StrictHostKeyChecking=no backend/alembic/versions/NEW.py root@217.149.29.227:/opt/im/backend/alembic/versions/
ssh impomento "docker cp /opt/im/backend/alembic/. im-backend:/app/alembic/ && docker exec im-backend uv run alembic upgrade head && /opt/im/deploy-backend.sh"

# Если добавили новый Python-пакет (Docker Hub недоступен с VPS, Aliyun mirror):
# ssh impomento "/opt/im/rebuild-backend.sh numpy другой-пакет"
# Этот скрипт: pip install через Aliyun → docker cp → restart → docker commit
```

**ВАЖНО про SSH**: SSH-ключ `~/.ssh/id_timeweb` теперь БЕЗ пароля. НЕ запускать множество SSH/SCP подряд без проверки соединения — иначе риск брутфорс-блокировки. Сначала `ssh impomento "echo ok"`.

---

## Дизайн-система

**Paper Light** (основная тема): bg `#F6F2E8`, text `#1A1714`, accent `#C9881E`, danger `#D54B3D`
**Darkroom** (камера и reveal): bg `#16100C`, text `#FFB347`

Шрифты: Fraunces (display), Inter (UI), JetBrains Mono, Caveat (script)

Токены: `analysis/design-screens/project/tokens.json`

---

## Текущий статус (2026-05-28)

### VPS
- **IP: `217.149.29.227`** (НЕ 89.169.39.236 — это старый IP в кэше)
- SSH alias: `impomento`, user: `root`, key: `~/.ssh/id_timeweb` (без пароля)
- Деплой: `scp -o StrictHostKeyChecking=no -r backend/app/ root@217.149.29.227:/opt/im/backend/app/`

### Готово ✅
- E2E флоу: регистрация → событие → QR → фото → альбом
- HTTPS продакшн на impomento.pro
- P25/P100 баг — исправлен и задеплоен (`_PLAN_LIMITS` в `event_service.py`)
- Рамка камеры PWA — пересчитывается по `video.videoWidth/Height` (CameraScreen.tsx)
- Все основные экраны Flutter и Guest PWA
- HaldCLUT LUT файлы скачаны (`guest-pwa/public/luts/`) — Portra 400, Fuji 400H, Ilford HP5+, Portra 800

### В РАБОТЕ — Фильтры плёнки (КРИТИЧНО)
**ВАЖНО**: пользователь дважды отверг попытки сделать фильтры через математические RGB-кривые + шум.
**Правильный подход**: HaldCLUT (профессиональные 3D LUT таблицы из t3mujinpack, MIT).
- Превью: `guest-pwa/public/filter-preview.html`
- Запуск: `cd guest-pwa/public && python -m http.server 8765` → открыть http://localhost:8765/filter-preview.html (НЕ через Vite — там HTTPS с самоподписанным cert)
- Pipeline: HaldCLUT (главное) → tungsten shift (cinestill) → halation (cinestill) → опц. grain/vignette
- **Перед интеграцией в src/utils/filmLut.ts — ОБЯЗАТЕЛЬНО показать превью пользователю**
- См. `memory/feedback_film_filters.md` и `memory/session_log_2026_05_28_opus.md` для полного контекста

### Осталось сделать
1. **Показать пользователю превью HaldCLUT** на его тестовых фото (`APK_app_test/photo_tests/`)
2. **Интегрировать HaldCLUT в `guest-pwa/src/utils/filmLut.ts`** — заменить математические кривые на загрузку и применение HaldCLUT файлов
3. **LUT на thumbnails** — `backend/app/workers/thumbnail.py` тоже использует те же HaldCLUT файлы через `pillow-lut-tools`
4. **WebGL ускорение фильтров** (опционально, для скорости на мобильных)
5. **RuStore** — публикация APK когда стабильно

---

## Важные правила работы

1. **MVP-фокус** — не усложнять, не добавлять фичи без явного запроса
2. **Без комментариев в коде** — только если причина неочевидна
3. **После каждой сессии** — сохранять session log в `memory/` (команда: "сохрани сессию")
4. **Перед переключением на Opus** — предупредить пользователя
5. **UI текст** — на русском, цены в ₽

---

## Полная память проекта

Подробная история всех сессий, решений и контекст: `memory/MEMORY.md`
