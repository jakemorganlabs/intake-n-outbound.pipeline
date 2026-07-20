-- Migration 004: dead-letter table. The global error sink.

CREATE TABLE IF NOT EXISTS dead_letter (
    dlq_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    lead_snapshot JSONB NOT NULL,
    stage TEXT NOT NULL,
    error TEXT NOT NULL,
    error_detail JSONB,
    alert_raised BOOLEAN NOT NULL DEFAULT false,
    resolved_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_dead_letter_created_at ON dead_letter(created_at);
-- partial indexes for the open-DLQ view operators actually use
CREATE INDEX IF NOT EXISTS idx_dead_letter_resolved_at ON dead_letter(resolved_at) WHERE resolved_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_dead_letter_alert_raised ON dead_letter(alert_raised) WHERE resolved_at IS NULL;

COMMENT ON TABLE dead_letter IS 'Global error sink. Every unhandled stage failure converges here and raises an operator alert.';
COMMENT ON COLUMN dead_letter.lead_snapshot IS 'Full lead state at time of failure; nothing is lost.';
COMMENT ON COLUMN dead_letter.stage IS 'The pipeline stage where the failure occurred (research, inference, outbound_x, ...).';
COMMENT ON COLUMN dead_letter.error_detail IS 'Structured payload for triage and filtering.';