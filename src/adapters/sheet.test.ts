// Sheets adapter unit test.

import { describe, it, expect } from 'vitest';
import { dispatchSheet } from './sheet.js';

describe('sheet adapter', () => {
  it('returns ok=false when GOOGLE_SHEET_ID is missing', async () => {
    const prev = process.env.GOOGLE_SHEET_ID;
    delete process.env.GOOGLE_SHEET_ID;

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
    expect(result.error).toContain('GOOGLE_SHEET_ID');

    if (prev !== undefined) process.env.GOOGLE_SHEET_ID = prev;
  });
});
