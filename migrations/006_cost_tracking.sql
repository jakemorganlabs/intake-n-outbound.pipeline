-- Migration 006: per-call cost tracking on inference_audit.
-- cost_cents is computed in the pipeline after each call; price_snapshot records the rates used.

ALTER TABLE inference_audit
ADD COLUMN IF NOT EXISTS cost_cents NUMERIC(12,4);

ALTER TABLE inference_audit
ADD COLUMN IF NOT EXISTS price_snapshot JSONB;

COMMENT ON COLUMN inference_audit.cost_cents IS 'Computed per-call cost in cents. Aggregated monthly for budget review.';
COMMENT ON COLUMN inference_audit.price_snapshot IS '{ model, rate_input, rate_output, source, recorded_at }';