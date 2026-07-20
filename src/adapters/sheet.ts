// Google Sheets append adapter. WARM tier writes one row per lead.

import 'dotenv/config';
import { withRetry, isRetryableHttp } from './retry.js';

const GOOGLE_SHEETS_API_KEY = process.env.GOOGLE_SHEETS_API_KEY || '';
const GOOGLE_SHEET_ID = process.env.GOOGLE_SHEET_ID || '';
const GOOGLE_SHEET_RANGE = process.env.GOOGLE_SHEET_RANGE || 'warm_leads!A1';

export interface SheetDispatchInput {
  leadId: string;
  idempotencyKey: string;
  name: string;
  email: string;
  company: string | null;
  composite: number;
  tier: string;
  scoredAt: string;
}

export interface AdapterResult {
  ok: boolean;
  latencyMs: number;
  statusCode?: number;
  error?: string;
}

export async function dispatchSheet(input: SheetDispatchInput): Promise<AdapterResult> {
  if (!GOOGLE_SHEETS_API_KEY || !GOOGLE_SHEET_ID) {
    return { ok: false, latencyMs: 0, error: 'GOOGLE_SHEETS_API_KEY or GOOGLE_SHEET_ID not configured' };
  }

  const start = Date.now();
  const values = [
    [
      input.scoredAt,
      input.name,
      input.email,
      input.company || input.email.split('@')[1] || '',
      String(input.composite),
      input.tier,
      input.leadId,
      input.idempotencyKey,
    ],
  ];

  async function attempt(): Promise<AdapterResult> {
    try {
      const res = await fetch(
        `https://sheets.googleapis.com/v4/spreadsheets/${GOOGLE_SHEET_ID}/values/${GOOGLE_SHEET_RANGE}:append?valueInputOption=USER_ENTERED&insertDataOption=INSERT_ROWS&key=${GOOGLE_SHEETS_API_KEY}`,
        {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ values }),
        }
      );
      const latencyMs = Date.now() - start;
      if (res.ok || res.status === 200 || res.status === 201) {
        return { ok: true, latencyMs, statusCode: res.status };
      }
      const bodyText = await res.text().catch(() => '');
      return { ok: false, latencyMs, statusCode: res.status, error: `Sheets ${res.status}: ${bodyText.slice(0, 200)}` };
    } catch (e) {
      return { ok: false, latencyMs: Date.now() - start, error: (e as Error).message };
    }
  }

  return withRetry(
    attempt,
    (r) => !r.ok && isRetryableHttp(r),
  );
}