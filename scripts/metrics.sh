#!/usr/bin/env bash
# Metrics reporter for MICT-PIPE-001
# Traces to: §17.3, NFR-OB-2
# Usage: DATABASE_URL=<url> ./scripts/metrics.sh

set -euo pipefail

DATABASE_URL="${DATABASE_URL:-postgresql://postgres:postgres@localhost:5432/intake_pipeline}"

PSQL="psql ${DATABASE_URL} --tuples-only --no-align"

echo "==================================================="
echo "Pipeline Metrics"
echo "==================================================="
echo ""

echo "--- Counters ---"
$PSQL -c "
SELECT
    event_type,
    COUNT(*) as count,
    MAX(event_time) as last_seen
FROM metrics_events
WHERE event_time > NOW() - INTERVAL '24 hours'
GROUP BY event_type
ORDER BY count DESC;
"

echo ""
echo "--- Leads by tier (last 24h) ---"
$PSQL -c "
SELECT
    routing->>'tier' as tier,
    COUNT(*) as count
FROM leads
WHERE received_at > NOW() - INTERVAL '24 hours'
GROUP BY routing->>'tier'
ORDER BY count DESC;
"

echo ""
echo "--- Inference health (last 24h) ---"
$PSQL -c "
SELECT
    validation_result,
    COUNT(*) as count,
    AVG(latency_ms)::int as avg_latency_ms
FROM inference_audit
WHERE recorded_at > NOW() - INTERVAL '24 hours'
GROUP BY validation_result
ORDER BY count DESC;
"

echo ""
echo "--- Dead-letter (last 24h) ---"
$PSQL -c "
SELECT
    COUNT(*) as unresolved,
    MAX(created_at) as newest
FROM dead_letter
WHERE resolved_at IS NULL
  AND created_at > NOW() - INTERVAL '24 hours';
"

echo ""
echo "--- Degraded leads (last 24h) ---"
$PSQL -c "
SELECT COUNT(*) as degraded_count
FROM leads
WHERE web_research->>'degraded' = 'true'
  AND received_at > NOW() - INTERVAL '24 hours';
"

echo ""
echo "--- Monthly cost ---"
./scripts/cost_monthly.sh

echo ""
echo "==================================================="
echo "Done"
