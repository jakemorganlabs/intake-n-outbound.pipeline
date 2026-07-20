// Slack incoming-webhook adapter. Used for HOT tier alerts and MANUAL / dispatch-failure alerts.

import 'dotenv/config';
import { withRetry, isRetryableHttp } from './retry.js';

const SLACK_WEBHOOK_URL = process.env.SLACK_WEBHOOK_URL || '';

export interface ChatDispatchInput {
  leadId: string;
  tier: string;
  summary: string;
  composite: number;
  confidence: number;
  name: string;
  email: string;
  message?: string;
}

export interface AdapterResult {
  ok: boolean;
  latencyMs: number;
  statusCode?: number;
  error?: string;
}

export async function dispatchChatAlert(input: ChatDispatchInput): Promise<AdapterResult> {
  if (!SLACK_WEBHOOK_URL) {
    return { ok: false, latencyMs: 0, error: 'SLACK_WEBHOOK_URL not configured' };
  }

  const start = Date.now();
  const body = {
    text: `Pipeline Alert: ${input.tier} lead detected\n` +
      `- Lead: ${input.name} (${input.email})\n` +
      `- Score: ${input.composite} / Confidence: ${input.confidence}\n` +
      `- Summary: ${input.summary}\n` +
      `- Record: ${input.leadId}`,
    blocks: [
      {
        type: 'header',
        text: { type: 'plain_text', text: `${input.tier} Lead: ${input.name}` },
      },
      {
        type: 'section',
        fields: [
          { type: 'mrkdwn', text: `*Score:* ${input.composite}` },
          { type: 'mrkdwn', text: `*Confidence:* ${input.confidence}` },
        ],
      },
      {
        type: 'section',
        text: { type: 'mrkdwn', text: input.summary || 'No summary' },
      },
    ],
  };

  async function attempt(): Promise<AdapterResult> {
    try {
      const res = await fetch(SLACK_WEBHOOK_URL, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(body),
      });
      const latencyMs = Date.now() - start;
      if (res.ok || res.status === 200 || res.status === 201) {
        return { ok: true, latencyMs, statusCode: res.status };
      }
      return { ok: false, latencyMs, statusCode: res.status, error: `Slack responded ${res.status}` };
    } catch (e) {
      return { ok: false, latencyMs: Date.now() - start, error: (e as Error).message };
    }
  }

  return withRetry(
    attempt,
    (r) => !r.ok && isRetryableHttp(r),
  );
}