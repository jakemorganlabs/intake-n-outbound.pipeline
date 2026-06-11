// CRM adapter (HubSpot contact create with dedupe key as external id)
// Traces to: §10.9 Outbound Adapters, FR-RT-2, FR-RT-5

import 'dotenv/config';
import { withRetry, isRetryableHttp } from './retry.js';

const HUBSPOT_API_KEY = process.env.HUBSPOT_API_KEY || '';
const HUBSPOT_BASE = 'https://api.hubapi.com';

export interface CRMDispatchInput {
  leadId: string;
  idempotencyKey: string;
  name: string;
  email: string;
  company: string | null;
  domain: string | null;
  summary: string;
  composite: number;
  tier: string;
}

export interface AdapterResult {
  ok: boolean;
  latencyMs: number;
  statusCode?: number;
  error?: string;
}

export async function dispatchCRM(input: CRMDispatchInput): Promise<AdapterResult> {
  if (!HUBSPOT_API_KEY) {
    return { ok: false, latencyMs: 0, error: 'HUBSPOT_API_KEY not configured' };
  }

  const start = Date.now();

  async function attempt(): Promise<AdapterResult> {
    try {
      const res = await fetch(`${HUBSPOT_BASE}/crm/v3/objects/contacts`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${HUBSPOT_API_KEY}`,
        },
        body: JSON.stringify({
          properties: {
            email: input.email,
            firstname: input.name.split(' ')[0] || input.name,
            lastname: input.name.split(' ').slice(1).join(' ') || '',
            company: input.company || input.domain || '',
            hs_external_id: input.idempotencyKey,
            lifecyclestage: 'lead',
            lead_source: 'intake_pipeline_webhook',
            notes_last_updated: new Date().toISOString(),
          },
        }),
      });
      const latencyMs = Date.now() - start;
      if (res.ok || res.status === 200 || res.status === 201) {
        return { ok: true, latencyMs, statusCode: res.status };
      }
      // HubSpot returns 409 for duplicate external id on some endpoints; here we use upsert-friendly create
      const bodyText = await res.text().catch(() => '');
      return { ok: false, latencyMs, statusCode: res.status, error: `HubSpot ${res.status}: ${bodyText.slice(0, 200)}` };
    } catch (e) {
      return { ok: false, latencyMs: Date.now() - start, error: (e as Error).message };
    }
  }

  return withRetry(
    attempt,
    (r) => !r.ok && isRetryableHttp(r),
  );
}
