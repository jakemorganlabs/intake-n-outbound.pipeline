-- Migration 005: counters (simple event table for observability)
-- Traces to: §17.2, §17.3 Metrics & Alerts, NFR-OB-2

CREATE TABLE IF NOT EXISTS metrics_events (
    event_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    event_type TEXT NOT NULL,
    event_time TIMESTAMPTZ NOT NULL DEFAULT now(),
    event_data JSONB NOT NULL DEFAULT '{}'
);

CREATE INDEX IF NOT EXISTS idx_metrics_events_type ON metrics_events(event_type);
CREATE INDEX IF NOT EXISTS idx_metrics_events_time ON metrics_events(event_time);

COMMENT ON TABLE metrics_events IS 'Simple event stream for counters. Aggregated by metrics queries and scripts.';
COMMENT ON COLUMN metrics_events.event_type IS 'e.g. leads_total, leads_by_tier, gate_failure, repair_used, search_degraded, dlq_entry';
