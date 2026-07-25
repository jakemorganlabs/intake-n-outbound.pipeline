import { Hono } from 'hono';
import { serve } from '@hono/node-server';
import { runPipeline } from './pipeline.js';

const app = new Hono();
const PORT = process.env.PORT ? parseInt(process.env.PORT, 10) : 3001;

// Flatten a Tally webhook payload into the flat {name,email,message,...} the pipeline reads.
// Matches Tally fields by label (case-insensitive). Non-Tally bodies pass through unchanged.
function adaptTally(raw: any): any {
  const fields = raw?.data?.fields;
  if (!Array.isArray(fields)) return raw; // not a Tally payload, leave as-is

  const pick = (needle: string) => {
    const f = fields.find((x: any) =>
      String(x?.label || '').toLowerCase().includes(needle)
    );
    return f?.value ?? '';
  };

  return {
    name: pick('name'),
    email: pick('email'),
    message: pick('message'),
    company: pick('company') || null,
    submission_id: raw?.data?.submissionId || raw?.eventId || null,
    form_id: raw?.data?.formId || 'tally',
    submitted_at: raw?.createdAt || new Date().toISOString(),
    raw_submission: raw,
  };
}

app.post('/intake-webhook', async (c) => {
  const raw = await c.req.json().catch(() => ({}));
  const body = adaptTally(raw);
  const headers: Record<string, string> = {};
  c.req.raw.headers.forEach((v, k) => { headers[k] = v; });

  const result = await runPipeline({ body, headers });
  return c.json(result.body as Record<string, unknown>, result.statusCode as 200 | 400 | 401 | 503);
});

app.get('/health', async (c) => {
  return c.json({ status: 'ok' });
});

const startedAt = new Date().toISOString();
console.log(`[${startedAt}] intake pipeline server started`);
console.log(`POST http://localhost:${PORT}/intake-webhook`);
console.log(`GET  http://localhost:${PORT}/health`);

serve({ fetch: app.fetch, port: PORT, hostname: '0.0.0.0' }, () => {
  console.log(`Server running on http://0.0.0.0:${PORT}`);
});

