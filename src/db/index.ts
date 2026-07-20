import { Pool } from 'pg';

const DATABASE_URL = process.env.DATABASE_URL ?? 'postgresql://postgres:postgres@localhost:5432/intake_pipeline';

// short connection timeout so CI fails fast instead of hanging
export const pool = new Pool({
  connectionString: DATABASE_URL,
  connectionTimeoutMillis: 5000,
});