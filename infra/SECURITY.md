# Безопасность — инструкция для деплоя

Полный набор проверок и действий перед публикацией в RuStore. Ссылка на детальный контекст: `analysis/business-plan/index.html` → секция 17.

## 1. YooKassa webhook — IP-whitelist

**Что сделано в коде:**
- `backend/app/api/v1/webhooks.py` — убрана HMAC-проверка подписи (YooKassa не подписывает payload)
- `infra/nginx.conf` — добавлен `location = /api/v1/webhooks/yookassa` с IP-whitelist

**Что проверить на VPS перед деплоем:**
1. Актуальные IP YooKassa: https://yookassa.ru/developers/using-api/webhooks#ip
2. Обновить `allow` строки в `nginx.conf` если IP изменились (проверять раз в квартал).
3. После деплоя тестовый webhook из личного кабинета YooKassa → должен вернуть 200.

## 2. CORS

**Что сделано:**
- `backend/app/main.py` — при `APP_ENV=production` требует `CORS_ORIGINS` быть непустым (иначе RuntimeError на старте)

**Что установить в .env на VPS:**
```
CORS_ORIGINS=["https://impomento.pro"]
```

## 3. S3 креды — ротация с `minioadmin`

**Что нужно сделать (ручная работа перед RuStore):**

1. Сгенерить новые креды длиной 32+ байт:
   ```bash
   openssl rand -hex 24  # 48-char access key
   openssl rand -hex 32  # 64-char secret key
   ```
2. Обновить в `/opt/im/backend.prod.env`:
   ```
   S3_ACCESS_KEY=<new_access_key>
   S3_SECRET_KEY=<new_secret_key>
   MINIO_ROOT_USER=<new_access_key>
   MINIO_ROOT_PASSWORD=<new_secret_key>
   ```
3. Перезапустить MinIO + backend:
   ```bash
   cd /opt/im && docker compose -f docker-compose.prod.yml restart minio backend im-worker
   ```
4. Проверить `/api/v1/guest/frames/presign` возвращает валидный URL.

**Альтернатива на production:** мигрировать с MinIO на Timeweb S3 (объектное хранилище, ~349₽/мес за 100 GB). См. `analysis/business-plan/index.html` → секция 04.

## 4. Rate limiting

**Что сделано:**
- `infra/nginx.conf` — новая зона `zone=auth:10m rate=10r/m` для `/api/v1/auth/*`
- Общий лимит `zone=api:10m rate=60r/m` для всех остальных `/api/v1/`

**Что проверить:** после деплоя `curl` на `/api/v1/auth/email/request` 11 раз с одного IP → 11-й запрос вернёт 429.

## 5. SSE-S3 encryption at rest

**Что сделано:**
- `backend/app/infra/s3_client.py:upload_bytes` — добавлен `ServerSideEncryption='AES256'`

**Что проверить на production:**
- Timeweb S3 поддерживает SSE-S3 автоматически, дополнительной настройки не требуется.
- MinIO локально игнорирует неизвестные SSE-заголовки (не сломается).

## 6. JWT_SECRET

**Что проверить перед RuStore:**
- `/opt/im/backend.prod.env` → `JWT_SECRET` должен быть ≥32 случайных символов.
- Сгенерить: `openssl rand -hex 32`

## 7. Postgres backup

**Что сделано:**
- `infra/backup-postgres.sh` — скрипт ежедневного бэкапа с ротацией 14 дней

**Что установить на VPS:**
```bash
# Скопировать скрипт
scp infra/backup-postgres.sh root@impomento:/opt/im/backup-postgres.sh
ssh impomento "chmod +x /opt/im/backup-postgres.sh"

# Добавить в cron (ежедневно в 3:00 МСК)
ssh impomento "echo '0 3 * * * /opt/im/backup-postgres.sh >> /var/log/im-backup.log 2>&1' | crontab -"

# Проверить cron
ssh impomento "crontab -l"

# Тестовый запуск
ssh impomento "/opt/im/backup-postgres.sh"
ssh impomento "ls -la /opt/im/backups/postgres/"
```

## 8. Согласие на ПД (152-ФЗ)

**Что нужно сделать (ручная работа):**
1. Создать `guest-pwa/public/offer.html` — шаблон юр.оферты
2. Создать `guest-pwa/public/privacy.html` — политика конфиденциальности
3. В Flutter регистрации добавить чекбокс «Я согласен с офертой и политикой ПД»

## Чек-лист перед RuStore submit

- [ ] YooKassa IP-whitelist в nginx активен, YooKassa тестовый webhook → 200
- [ ] `CORS_ORIGINS` в prod = `["https://impomento.pro"]`
- [ ] S3 креды ротированы (не `minioadmin`)
- [ ] `JWT_SECRET` в prod ≥32 байт
- [ ] Rate limiting: `/auth` возвращает 429 после 10 попыток/мин
- [ ] SSE-S3 работает (проверить в CloudLog upload'ов)
- [ ] pg_dump cron работает, файлы в `/opt/im/backups/postgres/`
- [ ] `/offer` и `/privacy` опубликованы
- [ ] Чекбокс согласия ПД в Flutter регистрации
- [ ] Логи не содержат PII (email/password/code)
