// Slack adapter unit test.

import { describe, it, expect } from 'vitest';
import { dispatchChatAlert } from './chat.js';

describe('chat adapter', () => {
  it('returns ok=false when SLACK_WEBHOOK_URL is missing', async () => {
    const result = await dispatchChatAlert({
      leadId: 'test-123',
      tier: 'HOT',
      summary: 'Test summary',
      composite: 96,
      confidence: 0.86,
      name: 'Test Name',
      email: 'test@example.com',
    });

    expect(result.ok).toBe(false);
    expect(result.error).toContain('SLACK_WEBHOOK_URL');
  });
});