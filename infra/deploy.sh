#!/bin/bash
# Запускать с сервера: bash deploy.sh
set -euo pipefail

REPO_DIR="/opt/important-memories"
INFRA_DIR="$REPO_DIR/infra"

echo "==> Обновление кода..."
cd "$REPO_DIR"
git pull origin main

echo "==> Сборка PWA..."
cd "$REPO_DIR/guest-pwa"
npm ci
npm run build

echo "==> Сборка и запуск контейнеров..."
cd "$INFRA_DIR"
docker compose -f docker-compose.prod.yml build backend
docker compose -f docker-compose.prod.yml run --rm migrate
docker compose -f docker-compose.prod.yml up -d

echo "==> Готово! Статус:"
docker compose -f docker-compose.prod.yml ps
