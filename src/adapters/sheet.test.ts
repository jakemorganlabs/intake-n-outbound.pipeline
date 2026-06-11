// Sheet adapter unit tests
// Traces to: §10.9 Outbound Adapters, FR-RT-3, FR-RT-5

import { describe, it, expect } from 'vitest';
import { dispatchSheet } from './sheet.js';

describe('sheet adapter', () => {
  it('returns ok=false when GOOGLE_SHEETS_API_KEY is missing', async () => {
    const result = await dispatchSheet({
      leadId: 'test-123',
      idempotencyKey: 'sub:test',
      name: 'Test Name',
      email: 'test@example.com',
      company: 'TestCorp',
      composite: 55,
      tier: 'WARM',
      scoredAt: new Date().toISOString(),
    });

    expect(result.ok).toBe(false);
    expect(result.error).toContain('GOOGLE_SHEETS_API_KEY');
  });
});
