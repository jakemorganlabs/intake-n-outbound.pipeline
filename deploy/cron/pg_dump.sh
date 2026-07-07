#!/usr/bin/env bash
set -euo pipefail

# deploy/cron/pg_dump.sh
# Nightly postgres backup, custom-format dump, 7-day retention.
# Crontab line (copy into the operator's crontab):
# 15 3 * * * cd /opt/intake-pipeline && ./deploy/cron/pg_dump.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
"cd" "$REPO_ROOT"

source deploy/.env.production

BACKUP_DIR="$REPO_ROOT/backups"
mkdir -p "$BACKUP_DIR"

DUMP_FILE="$BACKUP_DIR/pipe_$(date +%F).dump"
LOG_FILE="$BACKUP_DIR/backup.log"

echo "[$(date '+%F %T')] Starting backup..." >> "$LOG_FILE"

if docker compose -f deploy/docker-compose.yml exec -T postgres pg_dump -U "$POSTGRES_USER" -Fc "$POSTGRES_DB" > "$DUMP_FILE"; then
  echo "[$(date '+%F %T')] Backup written to $DUMP_FILE" >> "$LOG_FILE"
else
  echo "[$(date '+%F %T')] BACKUP FAILED" >> "$LOG_FILE"
  exit 1
fi

# 7-day rolling retention
DELETED=$(find "$BACKUP_DIR" -maxdepth 1 -type f -name '*.dump' -mtime +7 -print)
find "$BACKUP_DIR" -maxdepth 1 -type f -name '*.dump' -mtime +7 -delete

echo "[$(date '+%F %T')] Deleted files: $DELETED" >> "$LOG_FILE"

echo "[$(date '+%F %T')] Done." >> "$LOG_FILE"
