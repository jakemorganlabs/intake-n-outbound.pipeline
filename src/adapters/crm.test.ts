// CRM adapter unit tests
// Traces to: §10.9 Outbound Adapters, FR-RT-2, FR-RT-5

import { describe, it, expect } from 'vitest';
import { dispatchCRM } from './crm.js';

describe('crm adapter', () => {
  it('returns ok=false when HUBSPOT_API_KEY is missing', async () => {
    const result = await dispatchCRM({
      leadId: 'test-123',
      idempotencyKey: 'sub:test',
      name: 'Test Name',
      email: 'test@example.com',
      company: 'TestCorp',
      domain: null,
      summary: 'Test summary',
      composite: 96,
      tier: 'HOT',
    });

    expect(result.ok).toBe(false);
    expect(result.error).toContain('HUBSPOT_API_KEY');
  });
});
