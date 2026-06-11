// Metrics counter inserts for the pipeline.
// Traces to: §17.2, §17.3, NFR-OB-2

import { Client } from 'pg';

const DATABASE_URL = process.env.DATABASE_URL || 'postgresql://postgres:postgres@localhost:5432/intake_pipeline';

export async function recordMetric(
  eventType: string,
  eventData: Record<string, unknown> = {},
  client?: Client
): Promise<void> {
  const ownClient = !client;
  const pg = client || new Client({ connectionString: DATABASE_URL });

  try {
    if (ownClient) await pg.connect();
    await pg.query(
      'INSERT INTO metrics_events (event_type, event_data) VALUES ($1, $2)',
      [eventType, JSON.stringify(eventData)]
    );
  } finally {
    if (ownClient) await pg.end();
  }
}
