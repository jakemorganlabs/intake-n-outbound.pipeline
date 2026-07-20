-- Migration 002: canonical lead record.

CREATE TABLE IF NOT EXISTS leads (
    lead_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    idempotency_key TEXT NOT NULL UNIQUE REFERENCES dedupe(idempotency_key),
    received_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    status TEXT NOT NULL DEFAULT 'received',
    source JSONB NOT NULL DEFAULT '{}',
    raw_submission JSONB NOT NULL DEFAULT '{}',
    normalized JSONB NOT NULL DEFAULT '{}',
    web_research JSONB,
    enrichment JSONB,
    score JSONB,
    routing JSONB,
    errors JSONB DEFAULT '[]'::jsonb,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- partial-ish indexes for the operational queries (status counts, time-bounded scans)
CREATE INDEX IF NOT EXISTS idx_leads_status ON leads(status);
CREATE INDEX IF NOT EXISTS idx_leads_received_at ON leads(received_at);
CREATE INDEX IF NOT EXISTS idx_leads_idempotency_key ON leads(idempotency_key);

COMMENT ON TABLE leads IS 'Canonical lead record. One row per processed submission with full provenance.';
COMMENT ON COLUMN leads.status IS 'received | enriched | scored | routed | inference_failed | delivery_failed';