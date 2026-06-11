-- Migration 006: cost tracking on inference_audit
-- Traces to: §17.4, NFR-CO-1

-- Per-call cost in cents (tokens * rate_in + tokens * rate_out)
-- Recorded by the pipeline after each inference call.
ALTER TABLE inference_audit
ADD COLUMN IF NOT EXISTS cost_cents NUMERIC(12,4);

-- Price snapshot used at the time of the call
ALTER TABLE inference_audit
ADD COLUMN IF NOT EXISTS price_snapshot JSONB;

COMMENT ON COLUMN inference_audit.cost_cents IS 'Computed per-call cost in cents. Aggregated monthly for budget review.';
COMMENT ON COLUMN inference_audit.price_snapshot IS '{ model, rate_input, rate_output, source, recorded_at }';
