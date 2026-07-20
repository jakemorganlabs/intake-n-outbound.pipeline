#!/usr/bin/env bash
set -euo pipefail

# scripts/smoke_prod.sh
# External smoke test hitting the production webhook URL.
# Worked Example B payload (Appendix B of SRS): small business + clear intent.
# Asserts HTTP 200 and expected response shape via jq.
# Runs from any laptop; no VPS assumptions.

WEBHOOK_URL="https://intake.jakemorganlabs.dev/webhook"
RESULT=0

echo "POST $WEBHOOK_URL"

PAYLOAD='{
  "submission_id": "smoke-prod-"'$(date +%s)'",
  "name": "Laura Santos",
  "email": "laura.santos@greenvalefp.com",
  "company": "Greenvale Financial Planning",
  "message": "Looking to improve our client onboarding process for new advisor reviews. ~120 clients / quarter, ~$500k / year. Need HIPAA-compliant case-management.",
  "form_id": "smoke-test"
}'

RESPONSE=$(curl -s -w "\n%{http_code}\n" -X POST "$WEBHOOK_URL" \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD" \
  --max-time 30 \
  2>/dev/null || true)

# Split into body and status code
BODY=$(echo "$RESPONSE" | sed -n '1,$p' | sed '$d' | sed '$d')
HTTP=$(echo "$RESPONSE" | tail -n 1 | tr -d '\r')

if [ -z "$HTTP" ]; then
  echo "FAIL: no HTTP response (network error or timeout)"
  exit 1
fi

if [ "$HTTP" -ne 200 ]; then
  echo "FAIL: HTTP $HTTP"\n  echo "Body: $BODY"
  RESULT=1
else
  echo "HTTP 200 OK"

  # Shape assertions via jq (if available)
  if command -v jq &>/dev/null; then
    STATUS=$(echo "$BODY" | jq -r '.status // "MISSING"')
    TIER=$(echo "$BODY" | jq -r '.routing.tier // "MISSING"')
    LEAD_ID=$(echo "$BODY" | jq -r '.lead_id // "MISSING"')
    REPAIR=$(echo "$BODY" | jq -r '.repair_used // "MISSING"')

    echo "  status: $STATUS"
    echo "  tier: $TIER"
    echo "  lead_id: $LEAD_ID"
    echo "  repair_used: $REPAIR"

    if [ "$STATUS" != "routed" ]; then
      echo "FAIL: expected status 'routed', got '$STATUS'"
      RESULT=1
    fi

    if [ -z "$LEAD_ID" ] || [ "$LEAD_ID" = "MISSING" ]; then
      echo "FAIL: missing lead_id"
      RESULT=1
    fi
  else
    echo "  (jq not available; skipping body shape assertions)"
    echo "  Raw body: $BODY"
  fi

  echo ""
  echo "=== Operator verification steps ==="
  echo "1. SSH into the VPS and confirm lead row exists:"
  echo "   docker compose -f deploy/docker-compose.yml exec postgres psql -U <POSTGRES_USER> -d <POSTGRES_DB> -c \"SELECT lead_id, routing->>'tier', created_at FROM leads WHERE idempotency_key LIKE 'smoke%';\""
  echo "2. Check Slack #intake-alerts for a HOT-tier ping."
  echo "3. If tier is MANUAL, review inference_audit for the lead_id and determine API key/misconfiguration."
fi

echo ""
if [ $RESULT -eq 0 ]; then
  echo "SMOKE PASS"
else
  echo "SMOKE FAIL"
fi

exit $RESULT
