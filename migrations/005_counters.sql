-- Migration 005: simple event table for observability counters.

CREATE TABLE IF NOT EXISTS metrics_events (
    event_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    event_type TEXT NOT NULL,
    event_time TIMESTAMPTZ NOT NULL DEFAULT now(),
    event_data JSONB NOT NULL DEFAULT '{}'
);

CREATE INDEX IF NOT EXISTS idx_metrics_events_type ON metrics_events(event_type);
CREATE INDEX IF NOT EXISTS idx_metrics_events_time ON metrics_events(event_time);

COMMENT ON COLUMN metrics_events.event_type IS 'e.g. leads_total, leads_by_tier, gate_failures_total, repair_used, search_degraded, dlq_total';