#!/usr/bin/env bash
# Deploy latest code to the VPS and restart the pipeline service.
# Run from your laptop. Does not store SSH host in the repo.
#
# Usage:
#   VPS_HOST=user@your-vps-ip bash scripts/deploy.sh
#   # or run interactively and enter the host when prompted

set -euo pipefail

APP_DIR="${APP_DIR:-intake-pipeline}"
SERVICE_NAME="${SERVICE_NAME:-intake-pipeline}"
BRANCH="${BRANCH:-main}"

if [[ -z "${VPS_HOST:-}" ]]; then
  read -rp "Enter VPS SSH host (e.g. root@123.45.67.89): " VPS_HOST
fi

if [[ -z "$VPS_HOST" ]]; then
  echo "Error: VPS_HOST is required." >&2
  exit 1
fi

echo "Deploying to $VPS_HOST ($APP_DIR, branch $BRANCH)..."

ssh "$VPS_HOST" bash -s <<EOF
set -euo pipefail
cd "\$HOME/${APP_DIR}"

echo "Pulling latest code..."
git fetch origin
git checkout ${BRANCH}
git pull --ff-only origin ${BRANCH}

echo "Installing dependencies..."
npm ci

if [[ -f .env ]]; then
  set -a
  source .env
  set +a
fi

echo "Running migrations..."
npm run migrate

chmod +x scripts/start-server.sh

echo "Restarting ${SERVICE_NAME}..."
sudo systemctl restart ${SERVICE_NAME}.service
sleep 2
sudo systemctl is-active ${SERVICE_NAME}.service && echo "Deploy successful."
EOF

echo ""
echo "Health check (on VPS):"
echo "  ssh $VPS_HOST 'curl -s http://localhost:3001/health'"
