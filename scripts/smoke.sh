#!/usr/bin/env bash
# Smoke test. Posts labeled payloads and asserts end-to-end correctness per tier.
# Usage: ./scripts/smoke.sh [tier=all|hot|warm|cold|manual|chaos]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
PIDFILE="/tmp/intake-pipeline.pid"
SERVER_URL="${SERVER_URL:-http://localhost:3001}"
DATABASE_URL="${DATABASE_URL:-postgresql://postgres:postgres@localhost:5432/intake_pipeline}"
TIER="${1:-all}"

echo "=== Intake Pipeline Smoke Test ==="
echo "Project: $PROJECT_DIR"
echo "DB: ${DATABASE_URL##@*/}"
echo "Tier mode: $TIER"
echo ""

# -- Cleanup function --------------------------------------------------
cleanup() {
  if [[ -f "$PIDFILE" ]]; then
    kill "$(cat "$PIDFILE")" 2>/dev/null || true
    rm -f "$PIDFILE"
  fi
}
trap cleanup EXIT INT TERM

# -- Reset DB ----------------------------------------------------------
echo "[1/7] Resetting database..."
psql "$DATABASE_URL" -c "TRUNCATE leads, dedupe, inference_audit, dead_letter CASCADE;" >/dev/null 2>&1 || {
  echo "WARNING: could not truncate tables"
}

# -- Start server -------------------------------------------------------
echo "[2/7] Starting server on $SERVER_URL..."
npx tsx "$PROJECT_DIR/src/server.ts" > /tmp/intake-server.log 2>&1 &
echo $! > "$PIDFILE"

# Wait for server to be ready (max 15s)
for i in {1..30}; do
  if curl -sf "${SERVER_URL}/health" >/dev/null 2>&1; then
    break
  fi
  sleep 0.5
done

if ! curl -sf "${SERVER_URL}/health" >/dev/null; then
  echo "ERROR: server did not start"
  cat /tmp/intake-server.log || true
  exit 1
fi
echo "Server ready."

# -- Helper: post payload and assert status ----------------------------
post_payload() {
  local payload=$1
  local expect_status=$2
  local expect_tier=$3
  local label=$4

  echo "[$label] Posting payload..."
  RESPONSE=$(curl -sf -X POST "${SERVER_URL}/intake-webhook" \
    -H "Content-Type: application/json" \
    -d "$payload" | tr -d '\n')

  if ! echo "$RESPONSE" | grep -q "\"status\":\"$expect_status\""; then
    echo "FAIL: expected status $expect_status (got $RESPONSE)"
    return 1
  fi

  if ! echo "$RESPONSE" | grep -q "\"tier\":\"$expect_tier\""; then
    echo "FAIL: expected tier $expect_tier (got $RESPONSE)"
    return 1
  fi

  echo "PASS: $label"
  return 0
}

# -- Build payloads ----------------------------------------------------
PAYLOAD_HOT='{
  "name": "Dana Reyes",
  "email": "dreyes@northgate-medical.example",
  "message": "Opening an 18,000 sq ft outpatient clinic in Q3. Need Cat6A throughout plus a small server room. Quote needed by end of month -- budget is approved.",
  "company": "Northgate Medical Group",
  "form_id": "contact-form-001",
  "submitted_at": "2026-05-28T10:00:00Z",
  "submission_id": "submission-b-hot"
}'

PAYLOAD_WARM='{
  "name": "Sam Warm",
  "email": "swarm@example.com",
  "message": "Looking for a quote on network cabling for a small office. Budget is flexible.",
  "company": "Swarm Office",
  "form_id": "contact-form-002",
  "submitted_at": "2026-05-28T11:00:00Z",
  "submission_id": "submission-b-warm"
}'

PAYLOAD_COLD='{
  "name": "Alex Cold",
  "email": "acold@example.com",
  "message": "Just browsing, no immediate need.",
  "company": "Cold Inc",
  "form_id": "contact-form-003",
  "submitted_at": "2026-05-28T12:00:00Z",
  "submission_id": "submission-b-cold"
}'

EXIT_CODE=0

# -- Run tests per tier ------------------------------------------------
if [[ "$TIER" == "all" || "$TIER" == "hot" ]]; then
  post_payload "$PAYLOAD_HOT" "routed" "HOT" "TIER HOT" || EXIT_CODE=1
fi

if [[ "$TIER" == "all" || "$TIER" == "warm" ]]; then
  post_payload "$PAYLOAD_WARM" "routed" "WARM" "TIER WARM" || EXIT_CODE=1
fi

if [[ "$TIER" == "all" || "$TIER" == "cold" ]]; then
  post_payload "$PAYLOAD_COLD" "routed" "COLD" "TIER COLD" || EXIT_CODE=1
fi

if [[ "$TIER" == "all" || "$TIER" == "manual" ]]; then
  # MANUAL test: uses the double-invalid inference path
  echo "[TIER MANUAL] Posting payload that triggers MANUAL..."
  # We simulate this by pointing at a local mock that returns invalid schema,
  # but since this script uses the real server, we skip the assert and document.
  echo "SKIP: MANUAL tier requires a mocked inference; verify via scripts/smoke.ts"
fi

# -- Chaos test --------------------------------------------------------
if [[ "$TIER" == "all" || "$TIER" == "chaos" ]]; then
  echo "[CHAOS] Forcing adapter failure by pointing chat to localhost:9..."
  OLD_SLACK_WEBHOOK_URL="${SLACK_WEBHOOK_URL:-}"
  export SLACK_WEBHOOK_URL="http://localhost:9/fake-webhook"

  CHAOS_PAYLOAD='{
    "name": "Chaos Test",
    "email": "chaos@example.com",
    "message": "Chaos test for adapter failure handling",
    "company": "Chaos Inc",
    "form_id": "contact-form-chaos",
    "submitted_at": "2026-05-28T13:00:00Z",
    "submission_id": "submission-b-chaos"
  }'

  # Post a HOT payload; the chat adapter will fail because localhost:9 rejects.
  # The pipeline should still persist the lead and write DLQ + alert.
  CHAOS_RESPONSE=$(curl -sf -X POST "${SERVER_URL}/intake-webhook" \
    -H "Content-Type: application/json" \
    -d "$CHAOS_PAYLOAD" | tr -d '\n' || echo '{"status":"error"}')

  # Restore webhook URL
  if [[ -n "$OLD_SLACK_WEBHOOK_URL" ]]; then
    export SLACK_WEBHOOK_URL="$OLD_SLACK_WEBHOOK_URL"
  fi

  echo "[CHAOS] Verifying lead persisted despite adapter failure..."
  CHAOS_LEAD_COUNT=$(psql "$DATABASE_URL" -Atc "SELECT COUNT(*) FROM leads;")
  # We posted hot, warm, cold, manual, and now chaos - expecting 4 or 5 depending on tier mode
  if [[ "$CHAOS_LEAD_COUNT" -lt 4 ]]; then
    echo "FAIL: expected at least 4 lead rows, got $CHAOS_LEAD_COUNT"
    EXIT_CODE=1
  else
    echo "PASS: $CHAOS_LEAD_COUNT lead rows present"
  fi

  echo "[CHAOS] Verifying DLQ row exists..."
  DLQ_COUNT=$(psql "$DATABASE_URL" -Atc "SELECT COUNT(*) FROM dead_letter;")
  if [[ "$DLQ_COUNT" -lt 1 ]]; then
    echo "FAIL: expected at least 1 dead_letter row, got $DLQ_COUNT"
    EXIT_CODE=1
  else
    echo "PASS: $DLQ_COUNT dead_letter rows present"
  fi
fi

# -- Final summary ------------------------------------------------------
echo ""
if [[ $EXIT_CODE -eq 0 ]]; then
  echo "=== Smoke Test SUCESSFUL ==="
else
  echo "=== SOME CHECKS FAILED ==="
fi
exit $EXIT_CODE
