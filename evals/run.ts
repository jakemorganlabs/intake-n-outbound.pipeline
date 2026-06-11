// Eval runner for MICT-PIPE-001-S04
// Reads fixtures, posts to dev webhook, polls DB, asserts against labels.
// Usage: npm run eval [-- <category>]
//   <category> optional: schema | routing | idempotency | degradation | injection | gibberish | multilingual

import { readFileSync, readdirSync, statSync, writeFileSync } from 'fs';
import { join, dirname, resolve } from 'path';
import { fileURLToPath } from 'url';
import { Client } from 'pg';

const __dirname = dirname(fileURLToPath(import.meta.url));
const DATABASE_URL = process.env.DATABASE_URL || 'postgresql://postgres:postgres@localhost:5432/intake_pipeline';
const WEBHOOK_URL = process.env.EVAL_WEBHOOK_URL || 'http://localhost:3001/intake-webhook';
const FIXTURES_DIR = resolve(__dirname, 'fixtures');
const REPORT_PATH = resolve(__dirname, 'report.md');

interface Label {
  expected_status: 'routed' | 'inference_failed';
  tier_should_be: 'HOT' | 'WARM' | 'COLD' | 'MANUAL';
  valid: boolean;
  repair_used: boolean;
  notes?: string;
  degraded?: boolean;
  idempotent?: boolean;
  flags?: string[];
}

interface FixturePair {
  category: string;
  name: string;
  payload: Record<string, unknown>;
  label: Label;
}

interface Result {
  category: string;
  name: string;
  passed: boolean;
  errors: string[];
  latencies: { total: number };
}

function loadFixtures(categoryFilter?: string): FixturePair[] {
  const categories = readdirSync(FIXTURES_DIR).filter(name => {
    const p = join(FIXTURES_DIR, name);
    return statSync(p).isDirectory() && name !== 'templates';
  });

  const pairs: FixturePair[] = [];

  for (const category of categories) {
    if (categoryFilter && category !== categoryFilter) continue;
    const catDir = join(FIXTURES_DIR, category);
    const files = readdirSync(catDir)
      .filter(f => f.endsWith('.json') && !f.endsWith('.label.json'))
      .sort();

    for (const file of files) {
      const payloadPath = join(catDir, file);
      const labelPath = payloadPath.replace('.json', '.label.json');
      const payload = JSON.parse(readFileSync(payloadPath, 'utf-8'));
      const label = JSON.parse(readFileSync(labelPath, 'utf-8')) as Label;
      pairs.push({ category, name: file.replace('.json', ''), payload, label });
    }
  }

  return pairs;
}

function nowISO(): string {
  return new Date().toISOString();
}

function deriveIdempotencyKey(payload: Record<string, unknown>): string {
  const sid = (payload.submission_id as string) || null;
  if (sid) return `sub:${sid}`;
  // Fallback for fixtures that omit submission_id (none in current eval set)
  return `drv:unknown`;
}

async function resetTables(client: Client): Promise<void> {
  await client.query('DELETE FROM inference_audit');
  await client.query('DELETE FROM dead_letter');
  await client.query('DELETE FROM leads');
  await client.query('DELETE FROM dedupe');
}

async function postFixture(payload: Record<string, unknown>): Promise<{
  statusCode: number;
  body: Record<string, unknown>;
  latencyMs: number;
}> {
  const start = Date.now();
  const response = await fetch(WEBHOOK_URL, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(payload),
  });
  const latencyMs = Date.now() - start;
  const body = await response.json().catch(() => ({})) as Record<string, unknown>;
  return { statusCode: response.status, body, latencyMs };
}

async function pollLead(client: Client, idempotencyKey: string): Promise<Record<string, unknown> | null> {
  // Poll up to 20 times, 500ms apart --> max 10s
  for (let i = 0; i < 20; i++) {
    const result = await client.query(
      'SELECT * FROM leads WHERE idempotency_key = $1',
      [idempotencyKey]
    );
    if (result.rows.length > 0) {
      return result.rows[0] as Record<string, unknown>;
    }
    await new Promise(r => setTimeout(r, 500));
  }
  return null;
}

async function runFixture(
  pair: FixturePair,
  client: Client,
  seenKeys: Map<string, { leadId: string; rowCount: number }>
): Promise<Result> {
  const { category, name, payload, label } = pair;
  const errors: string[] = [];

  const sid = (payload.submission_id as string) || null;
  const idempotencyKey = sid ? `sub:${sid}` : `drv:unknown`;

  const startTotal = Date.now();

  // Post to webhook
  const { statusCode, body, latencyMs } = await postFixture(payload);

  // Check immediate HTTP status
  if (statusCode !== 200) {
    errors.push(`HTTP ${statusCode} instead of 200`);
  }

  // Poll DB for the row
  const leadRow = await pollLead(client, idempotencyKey);
  if (!leadRow) {
    errors.push('No lead row found in DB after polling');
  }

  // Check status
  const status = String((body?.status ?? leadRow?.status ?? ''));
  if (status !== label.expected_status) {
    errors.push(`Status: expected ${label.expected_status}, got ${status}`);
  }

  // Check tier
  const routing = (body?.routing ?? leadRow?.routing) as Record<string, unknown> | undefined;
  const tier = routing ? String(routing.tier ?? '') : String(body?.tier ?? '');
  if (tier !== label.tier_should_be) {
    errors.push(`Tier: expected ${label.tier_should_be}, got ${tier}`);
  }

  // Check degraded flag
  const degraded = (body?.degraded ?? leadRow?.degraded) as boolean | undefined;
  if (label.degraded !== undefined) {
    if (!!degraded !== label.degraded) {
      errors.push(`Degraded: expected ${label.degraded}, got ${!!degraded}`);
    }
  }

  // Check repair_used
  const bodyRepair = (body?.repair_used ?? undefined) as boolean | undefined;
  if (bodyRepair !== undefined && bodyRepair !== label.repair_used) {
    errors.push(`Repair: expected ${label.repair_used}, got ${bodyRepair}`);
  }

  // For idempotency fixtures, verify duplicate detection across the pair.
  const leadId = String(body?.lead_id ?? leadRow?.lead_id ?? '');
  if (label.idempotent !== undefined) {
    if (seenKeys.has(idempotencyKey)) {
      // This is a duplicate submission; should return same lead_id.
      const prev = seenKeys.get(idempotencyKey)!;
      if (leadId && prev.leadId !== leadId) {
        errors.push(
          `Idempotency: duplicate had different lead_id (${leadId} vs ${prev.leadId})`
        );
      }
    } else {
      // First time we see this key; store leadId.
      if (leadId) {
        seenKeys.set(idempotencyKey, { leadId, rowCount: 0 });
      }
    }
  }

  const totalLatency = Date.now() - startTotal;
  return {
    category,
    name,
    passed: errors.length === 0,
    errors,
    latencies: { total: totalLatency },
  };
}

async function main() {
  const categoryFilter = process.argv[2];

  // Connect to DB
  const client = new Client({ connectionString: DATABASE_URL });
  await client.connect();

  try {
    // Reset eval environment
    await resetTables(client);

    // Load fixtures
    const pairs = loadFixtures(categoryFilter);
    console.log(`Loaded ${pairs.length} fixture pairs`);

    const results: Result[] = [];
    const byCategory: Record<string, { pass: number; fail: number }> = {};
    const seenKeys = new Map<string, { leadId: string; rowCount: number }>();

    for (const pair of pairs) {
      if (!byCategory[pair.category]) byCategory[pair.category] = { pass: 0, fail: 0 };

      process.stdout.write(`[${pair.category}] ${pair.name} ... `);
      const result = await runFixture(pair, client, seenKeys);
      results.push(result);

      if (result.passed) {
        byCategory[pair.category].pass++;
        console.log('PASS');
      } else {
        byCategory[pair.category].fail++;
        console.log(`FAIL: ${result.errors.join('; ')}`);
      }
    }

    // Generate report
    const reportLines: string[] = [
      '# Eval Report — MICT-PIPE-001',
      '',
      `Generated: ${nowISO()}`,
      `Total fixtures: ${pairs.length}`,
      '',
      '## Summary',
      '',
      '| Category | Pass | Fail |',
      '|----------|------|------|',
    ];

    let totalPass = 0;
    let totalFail = 0;

    for (const cat of Object.keys(byCategory).sort()) {
      const { pass, fail } = byCategory[cat];
      totalPass += pass;
      totalFail += fail;
      reportLines.push(`| ${cat} | ${pass} | ${fail} |`);
    }

    reportLines.push(`| **Total** | **${totalPass}** | **${totalFail}** |`);
    reportLines.push('');

    // Failure detail table
    const failures = results.filter(r => !r.passed);
    if (failures.length > 0) {
      reportLines.push('## Failures');
      reportLines.push('');
      reportLines.push('| Fixture | Category | Error(s) |');
      reportLines.push('|---------|----------|----------|');
      for (const f of failures) {
        reportLines.push(`| ${f.name} | ${f.category} | ${f.errors.join('; ')} |`);
      }
      reportLines.push('');
    }

    // Passed list
    reportLines.push('## Passed Fixtures');
    reportLines.push('');
    for (const cat of Object.keys(byCategory).sort()) {
      const passes = results.filter(r => r.category === cat && r.passed);
      if (passes.length > 0) {
        reportLines.push(`### ${cat}`);
        for (const p of passes) {
          reportLines.push(`- ${p.name}: PASS (${p.latencies.total}ms)`);
        }
        reportLines.push('');
      }
    }

    reportLines.push('---');
    reportLines.push('*End of report*');

    const report = reportLines.join('\n');
    writeFileSync(REPORT_PATH, report);
    console.log(`\nReport written to ${REPORT_PATH}`);

    if (totalFail > 0) {
      console.log(`\nFAILURE: ${totalFail} of ${pairs.length} fixtures failed.`);
      process.exitCode = 1;
    } else {
      console.log(`\nSUCCESS: All ${pairs.length} fixtures passed.`);
      process.exitCode = 0;
    }
  } finally {
    await client.end();
  }
}

main().catch(e => {
  console.error('Fatal error:', e.message);
  process.exit(1);
});
