// Dead-letter writer. Captures a lead snapshot plus the failing stage and error.

import { pool } from '../db/index.js';

export interface DeadLetterInput {
  leadSnapshot: Record<string, unknown>;
  stage: string;
  error: string;
  errorDetail?: Record<string, unknown>;
}

export interface AdapterResult {
  ok: boolean;
  latencyMs: number;
  statusCode?: number;
  error?: string;
}

export interface DLQResult {
  dlqId: string;
  alertRaised: boolean;
}

export async function writeDeadLetter(input: DeadLetterInput): Promise<DLQResult> {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    const sql = `INSERT INTO dead_letter
      (lead_snapshot, stage, error, error_detail)
      VALUES ($1,$2,$3,$4)
      RETURNING dlq_id`;

    const result = await client.query(sql, [
      JSON.stringify(input.leadSnapshot),
      input.stage,
      input.error,
      input.errorDetail ? JSON.stringify(input.errorDetail) : null,
    ]);

    await client.query('COMMIT');
    const dlqId = result.rows[0]?.dlq_id as string;
    return { dlqId, alertRaised: true };
  } catch (e) {
    await client.query('ROLLBACK').catch(() => {});
    throw e;
  } finally {
    client.release();
  }
}