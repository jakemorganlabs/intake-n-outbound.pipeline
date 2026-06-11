#!/usr/bin/env bash
# Monthly cost aggregation
# Traces to: §17.4, NFR-CO-1
# Usage: DATABASE_URL=<url> ./scripts/cost_monthly.sh

set -euo pipefail

DATABASE_URL="${DATABASE_URL:-postgresql://postgres:postgres@localhost:5432/intake_pipeline}"
PSQL="psql ${DATABASE_URL} --tuples-only --no-align"

# Prices in cents per 1M tokens (example rates for Claude Haiku 3.5)
# Override via env vars if needed
RATE_IN_CENTS_PER_1M="${RATE_IN_CENTS_PER_1M:-25}"
RATE_OUT_CENTS_PER_1M="${RATE_OUT_CENTS_PER_1M:-125}"

compute_cost(){
    local in_tokens=$1
    local out_tokens=$2
    python3 -c "
rate_in = float('${RATE_IN_CENTS_PER_1M}') / 1e6
rate_out = float('${RATE_OUT_CENTS_PER_1M}') / 1e6
print(f'{in_tokens * rate_in + out_tokens * rate_out:.4f}')
"
}

# Update past 30 days of uncomputed rows
$PSQL -c "
UPDATE inference_audit
SET cost_cents = (
    (prompt_tokens * ${RATE_IN_CENTS_PER_1M} / 1000000.0) +
    (completion_tokens * ${RATE_OUT_CENTS_PER_1M} / 1000000.0)
)::numeric(12,4)
WHERE cost_cents IS NULL
  AND recorded_at > NOW() - INTERVAL '30 days'
  AND prompt_tokens IS NOT NULL
  AND completion_tokens IS NOT NULL;
"

echo "--- Monthly cost summary ---"
$PSQL -c "
SELECT
    DATE_TRUNC('month', recorded_at)::date as month,
    COUNT(*) as calls,
    SUM(prompt_tokens) as total_input_tokens,
    SUM(completion_tokens) as total_output_tokens,
    ROUND(SUM(cost_cents), 4) as total_cost_cents,
    ROUND(AVG(cost_cents), 6) as avg_cost_per_call_cents
FROM inference_audit
WHERE recorded_at > NOW() - INTERVAL '3 months'
GROUP BY DATE_TRUNC('month', recorded_at)
ORDER BY month DESC;
"

echo ""
echo "--- Price config snapshot ---"
echo "Rate input: ${RATE_IN_CENTS_PER_1M} cents / 1M tokens"
echo "Rate output: ${RATE_OUT_CENTS_PER_1M} cents / 1M tokens"
echo "Verify against current provider pricing if >90 days old."
