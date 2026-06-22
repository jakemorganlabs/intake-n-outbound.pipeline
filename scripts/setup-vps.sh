#!/usr/bin/env bash
# Interactive VPS installer for the intake pipeline.
# Run once after SSHing into a fresh Hetzner (or other Linux) VPS.
# Creates .env locally on the server — never commits secrets to git.

set -euo pipefail

REPO_URL="${REPO_URL:-https://github.com/jakemorganlabs/intake-n-outbound.pipeline.git}"
APP_DIR="${APP_DIR:-$HOME/intake-pipeline}"
DB_NAME="${DB_NAME:-intake_pipeline}"
DB_USER="${DB_USER:-postgres}"
SERVICE_NAME="${SERVICE_NAME:-intake-pipeline}"

echo "=== Intake Pipeline VPS Setup ==="
echo "App directory: $APP_DIR"
echo ""

# --- System dependencies -----------------------------------------------------

if ! command -v node &>/dev/null; then
  echo "Installing Node.js 22..."
  curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
  sudo apt-get install -y nodejs
else
  NODE_MAJOR="$(node -v | sed 's/^v//' | cut -d. -f1)"
  if [[ "$NODE_MAJOR" -lt 20 ]]; then
    echo "Node.js $(node -v) is too old. Installing Node.js 22..."
    curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
    sudo apt-get install -y nodejs
  else
    echo "Node.js $(node -v) OK"
  fi
fi

if ! command -v psql &>/dev/null; then
  echo "Installing PostgreSQL..."
  sudo apt-get update
  sudo apt-get install -y postgresql postgresql-contrib
  sudo systemctl enable postgresql
  sudo systemctl start postgresql
else
  echo "PostgreSQL OK"
fi

if ! command -v git &>/dev/null; then
  echo "Installing git..."
  sudo apt-get update
  sudo apt-get install -y git
fi

# --- Database ----------------------------------------------------------------

echo "Ensuring database '$DB_NAME' exists..."
sudo -u postgres psql -tc "SELECT 1 FROM pg_database WHERE datname = '$DB_NAME'" | grep -q 1 \
  || sudo -u postgres psql -c "CREATE DATABASE $DB_NAME;"
echo "Database OK"

# --- Application code --------------------------------------------------------

if [[ ! -d "$APP_DIR/.git" ]]; then
  echo "Cloning repository..."
  git clone "$REPO_URL" "$APP_DIR"
else
  echo "Repository already present at $APP_DIR"
fi

cd "$APP_DIR"
git pull --ff-only || true

echo "Installing npm dependencies..."
npm ci

DATABASE_URL="postgresql://${DB_USER}@localhost:5432/${DB_NAME}"
export DATABASE_URL
echo "Running migrations..."
npm run migrate

# --- Interactive secrets (.env) ----------------------------------------------

prompt_secret() {
  local var_name="$1"
  local description="$2"
  local example="${3:-}"
  local required="${4:-false}"

  echo ""
  echo "----------------------------------------"
  echo "$description"
  if [[ -n "$example" ]]; then
    echo "Example: $example"
  fi
  if [[ "$required" == "true" ]]; then
    echo "(Required)"
  else
    echo "(Optional — press Enter to skip)"
  fi

  local value=""
  while true; do
    read -rp "Enter $var_name: " value
    if [[ -n "$value" ]]; then
      break
    fi
    if [[ "$required" != "true" ]]; then
      break
    fi
    echo "This value is required. Please enter a value."
  done

  if [[ -n "$value" ]]; then
    # Escape double quotes in value for .env safety
    value="${value//\"/\\\"}"
    echo "${var_name}=\"${value}\"" >> .env
  fi
}

echo ""
echo "=== API Key Setup ==="
echo "You will be prompted for each secret one at a time."
echo "Values are written only to $APP_DIR/.env (never committed to git)."
echo ""

# Start fresh .env with non-secret defaults
cat > .env <<EOF
DATABASE_URL="postgresql://${DB_USER}@localhost:5432/${DB_NAME}"
MODEL_ID="google/gemma-4-26B-A4B-it"
PORT=3001
GOOGLE_SHEET_RANGE="warm_leads!A1"
EOF

prompt_secret "INFERENCE_API_KEY" \
  "DeepInfra API key — powers Gemma 4 structured JSON enrichment for each lead." \
  "di-..." \
  "true"

prompt_secret "MODEL_API_KEY" \
  "Model API key alias (optional) — same as INFERENCE_API_KEY if your tooling expects MODEL_API_KEY." \
  "di-..." \
  "false"

prompt_secret "SEARCH_API_KEY" \
  "Brave Search API key — web research enrichment on the lead's company/domain (fail-open if missing)." \
  "BS..." \
  "false"

prompt_secret "WEBHOOK_SECRET" \
  "Webhook secret — verifies HMAC signatures from your public form (e.g. Tally)." \
  "a-long-random-string" \
  "true"

prompt_secret "SLACK_WEBHOOK_URL" \
  "Slack incoming webhook — HOT tier alerts are posted here." \
  "https://hooks.slack.com/services/T000/B000/XXXX" \
  "false"

prompt_secret "HUBSPOT_API_KEY" \
  "HubSpot private app token — HOT tier creates CRM contacts." \
  "pat-na1-..." \
  "false"

prompt_secret "GOOGLE_SHEETS_API_KEY" \
  "Google Sheets API key — WARM tier appends rows to a spreadsheet." \
  "" \
  "false"

prompt_secret "GOOGLE_SHEET_ID" \
  "Google Sheet ID — target spreadsheet for WARM leads." \
  "1BxiMVs0XRA5nFMdKvBdBZjgmUUqptlbs74OgvE2upms" \
  "false"

chmod 600 .env

# --- systemd service ---------------------------------------------------------

DEPLOY_USER="$(whoami)"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"

echo ""
echo "=== Installing systemd service ==="
chmod +x scripts/start-server.sh

sudo sed \
  -e "s|REPLACE_WITH_DEPLOY_USER|${DEPLOY_USER}|g" \
  scripts/pipeline.service | sudo tee "$SERVICE_FILE" > /dev/null

sudo systemctl daemon-reload
sudo systemctl enable "${SERVICE_NAME}.service"
sudo systemctl restart "${SERVICE_NAME}.service"

sleep 2
if sudo systemctl is-active --quiet "${SERVICE_NAME}.service"; then
  echo "Service is running."
else
  echo "Service failed to start. Check logs:"
  echo "  sudo journalctl -u ${SERVICE_NAME} -n 50 --no-pager"
fi

# --- Done --------------------------------------------------------------------

echo ""
echo "=== Setup Complete ==="
echo "Secrets file: $APP_DIR/.env (mode 600, gitignored)"
echo "Health check: curl -s http://localhost:3001/health"
echo ""
echo "Routing tiers:"
echo "  HOT  -> Slack + HubSpot CRM"
echo "  WARM -> Google Sheets"
echo "  COLD -> Log only (Postgres)"
echo ""
echo "Point your Tally form webhook to:"
echo "  POST https://<your-vps-host>/intake-webhook"
echo ""
echo "Useful commands:"
echo "  sudo systemctl status ${SERVICE_NAME}"
echo "  sudo journalctl -u ${SERVICE_NAME} -f"
echo "  bash scripts/deploy.sh   # after future git updates"
