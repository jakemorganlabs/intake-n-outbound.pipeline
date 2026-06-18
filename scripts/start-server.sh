#!/usr/bin/env bash
# Load .env and start the HTTP webhook server.
# Used by systemd (pipeline.service) or manual runs on the VPS.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$APP_DIR"

if [[ -f .env ]]; then
  set -a
  # shellcheck disable=SC1091
  source .env
  set +a
else
  echo "Warning: .env not found in $APP_DIR" >&2
fi

export PORT="${PORT:-3001}"

exec npx tsx src/server.ts
