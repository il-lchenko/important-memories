#!/bin/bash
# Ежедневный бэкап Postgres → /opt/im/backups/postgres/
# Запускается через cron: 0 3 * * * /opt/im/backup-postgres.sh
#
# Хранит последние 14 дней локально. Удаляет более старые.
# TODO: после подтверждения работы — загружать в Timeweb S3 backup (см. TIMEWEB_BACKUP_MC).
set -euo pipefail

BACKUP_DIR="/opt/im/backups/postgres"
CONTAINER_NAME="im-postgres"
DB_USER="${POSTGRES_USER:-imuser}"
DB_NAME="${POSTGRES_DB:-im}"
RETENTION_DAYS=14

DATE=$(date +%Y%m%d_%H%M%S)
FILE="$BACKUP_DIR/im-$DATE.sql.gz"

mkdir -p "$BACKUP_DIR"

echo "[$(date -Iseconds)] Backing up $DB_NAME → $FILE"
docker exec "$CONTAINER_NAME" pg_dump -U "$DB_USER" "$DB_NAME" | gzip > "$FILE"

# Check backup is non-empty
SIZE=$(stat -c%s "$FILE" 2>/dev/null || stat -f%z "$FILE")
if [ "$SIZE" -lt 1000 ]; then
    echo "ERROR: backup file too small ($SIZE bytes) — aborting cleanup"
    exit 1
fi

echo "[$(date -Iseconds)] Backup OK, $SIZE bytes"

# Cleanup old backups
find "$BACKUP_DIR" -name "im-*.sql.gz" -mtime +$RETENTION_DAYS -delete
echo "[$(date -Iseconds)] Cleanup: removed backups older than $RETENTION_DAYS days"

# Optional: upload to Timeweb S3 backup bucket (uncomment when configured)
# TIMEWEB_BACKUP_MC="tw-backup"
# if command -v mc &>/dev/null; then
#     mc cp "$FILE" "$TIMEWEB_BACKUP_MC/im-postgres-backups/$(basename $FILE)"
# fi
