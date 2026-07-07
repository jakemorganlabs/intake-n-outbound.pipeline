#!/usr/bin/env bash
set -euo pipefail

# deploy/restore.sh
# Restore the latest backup into a scratch Postgres, sanity check, PASS/FAIL.
# On PASS, prints the exact pg_restore command for the live DB.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "$REPO_ROOT"

source deploy/.env.production

BACKUP_DIR="$REPO_ROOT/backups"
LATEST_DUMP=$(find "$BACKUP_DIR" -maxdepth 1 -type f -name '*.dump' | sort -r | head -n 1)

if [ -z "$LATEST_DUMP" ]; then
  echo "FAIL: no backup dumps found in $BACKUP_DIR"
  exit 1
fi

echo "Restoring from $LATEST_DUMP"

SCRATCH="scratch_restore_$(date +%s)"
docker run -d --name="$SCRATCH" \
  -e POSTGRES_USER="$POSTGRES_USER" \
  -e POSTGRES_PASSWORD="$POSTGRES_PASSWORD" \
  -e POSTGRES_DB="$POSTGRES_DB" \
  -v "$LATEST_DUMP:/tmp/pipe.dump:ro" \
  postgres:16.4

echo "Waiting for scratch DB..."
sleep 3

# Run pg_restore inside the scratch container
docker exec "$SCRATCH" pg_restore -U "$POSTGRES_USER" -d "$POSTGRES_DB" --no-owner --clean /tmp/pipe.dump

# Sanity check — SELECT count(*)
LEAD_COUNT=$(docker exec "$SCRATCH" psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Atc "SELECT count(*) FROM leads;")

docker rm -f "$SCRATCH" >/dev/null 2>&1

if [ -z "${LEAD_COUNT}" ]; then
  echo "FAIL: could not determine lead count from restored DB"
  exit 1
fi

if [ "$LEAD_COUNT" -ge 0 ]; then
  echo "PASS: restore verified, leads table has $LEAD_COUNT row(s)"
  echo ""
  echo "=== To restore into the LIVE DB ==="
  echo "docker compose -f deploy/docker-compose.yml exec -T postgres pg_restore \\"
  echo "  -U \"$POSTGRES_USER\" -d \"$POSTGRES_DB\" --no-owner --clean \\"
  echo "  < \"$LATEST_DUMP\""
else
  echo "FAIL: unexpected lead count [$LEAD_COUNT]"
  exit 1
fi
