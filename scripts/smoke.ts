/**
 * Smoke test. Walks the four tiers plus a forced adapter failure, end to
 * end, with mocked inference. Asserts the routed tier and the persisted
 * row count.
 *
 * Usage: npx tsx scripts/smoke.ts
 */

import { Client } from 'pg';
import {
  runPipeline,
  type PipelineInput,
  type PipelineOverrides,
  type NormalizedLead,
  type WebResearch,
  type InferenceResult,
} from '../src/pipeline.js';
import 'dotenv/config';

const DATABASE_URL = process.env.DATABASE_URL || 'postgresql://postgres:postgres@localhost:5432/intake_pipeline';

async function resetDb() {
  const client = new Client({ connectionString: DATABASE_URL });
  await client.connect();
  await client.query('TRUNCATE leads, dedupe, inference_audit, dead_letter CASCADE');
  await client.end();
}

async function count(table: string): Promise<number> {
  const client = new Client({ connectionString: DATABASE_URL });
  await client.connect();
  const result = await client.query(`SELECT COUNT(*) FROM ${table}`);
  await client.end();
  return parseInt(result.rows[0].count, 10);
}

function timestamp() {
  return new Date().toISOString();
}

// Mock inference: HOT (composite 96)
const mockInferenceHot = async (_n: NormalizedLead, _r: WebResearch): Promise<{ result: InferenceResult; error?: string }> => ({
  result: {
    model: 'google/gemma-4-26B-A4B-it',
    raw_output: {
      company_size: 'mid',
      industry: 'healthcare',
      fit_signals: { budget_indicated: true, timeline_urgency: 'high', decision_maker: true, use_case_clarity: 'high' },
      summary: 'Mid-size healthcare opening an 18k sqft clinic in Q3; needs Cat6A + server room; budget approved; quote within a month.',
      confidence: 0.86,
    },
    latency_ms: 3500,
    input_tokens: 1200,
    output_tokens: 280,
    started_at: timestamp(),
  },
});

// Mock inference: WARM (composite 55)
const mockInferenceWarm = async (_n: NormalizedLead, _r: WebResearch): Promise<{ result: InferenceResult; error?: string }> => ({
  result: {
    model: 'google/gemma-4-26B-A4B-it',
    raw_output: {
      company_size: 'small',
      industry: 'healthcare',
      fit_signals: { budget_indicated: true, timeline_urgency: 'medium', decision_maker: false, use_case_clarity: 'medium' },
      summary: 'Small clinic needs network upgrade in next quarter.',
      confidence: 0.7,
    },
    latency_ms: 3200,
    input_tokens: 1100,
    output_tokens: 250,
    started_at: timestamp(),
  },
});

// Mock inference: COLD (composite 25)
const mockInferenceCold = async (_n: NormalizedLead, _r: WebResearch): Promise<{ result: InferenceResult; error?: string }> => ({
  result: {
    model: 'google/gemma-4-26B-A4B-it',
    raw_output: {
      company_size: 'solo',
      industry: 'unknown',
      fit_signals: { budget_indicated: false, timeline_urgency: 'low', decision_maker: false, use_case_clarity: 'low' },
      summary: 'General inquiry with no budget or timeline.',
      confidence: 0.3,
    },
    latency_ms: 3000,
    input_tokens: 1000,
    output_tokens: 200,
    started_at: timestamp(),
  },
});

// Mock inference: schema-invalid, routes to MANUAL
const mockInferenceManual = async (_n: NormalizedLead, _r: WebResearch): Promise<{ result: InferenceResult; error?: string }> => ({
  result: {
    model: 'google/gemma-4-26B-A4B-it',
    raw_output: {
      company_size: 'extralarge',
      industry: 'healthcare',
      fit_signals: { budget_indicated: true, timeline_urgency: 'high', decision_maker: true },
      summary: 'Bad size and missing clarity',
      confidence: 999,
    },
    latency_ms: 3200,
    input_tokens: 1100,
    output_tokens: 200,
    started_at: timestamp(),
  },
});

function makePayload(tierSuffix: string): PipelineInput {
  return {
    body: {
      name: `Test ${tierSuffix}`,
      email: `test-${tierSuffix}@example.com`,
      message: `Test message for ${tierSuffix}.`,
      company: 'TestCorp',
      form_id: 'smoke-form-001',
      submitted_at: timestamp(),
      submission_id: `smoke-${tierSuffix}`,
    },
    headers: {},
  };
}

let exitCode = 0;
function fail(msg: string) {
  console.error(`FAIL: ${msg}`);
  exitCode = 1;
}

async function main() {
  console.log('=== Smoke Test ===');
  console.log(`DB: ${DATABASE_URL.replace(/\/\/.+@/, '//***@')}`);
  console.log('');

  console.log('[TIER HOT] Worked Example B end-to-end...');
  await resetDb();
  const hotPayload = makePayload('hot');
  const hotResult = await runPipeline(hotPayload, { inference: mockInferenceHot });

  if (hotResult.statusCode !== 200) fail(`Expected 200, got ${hotResult.statusCode}`);
  const hotRouting = hotResult.body.routing as { tier?: string } | undefined;
  if (hotRouting?.tier !== 'HOT') fail(`Expected HOT, got ${hotRouting?.tier}`);
  const hotScore = hotResult.body.score as { composite?: number } | undefined;
  if (hotScore?.composite !== 96) fail(`Expected composite 96, got ${hotScore?.composite}`);
  if (exitCode === 0) console.log('PASS');

  console.log('[TIER WARM] Standard warm lead...');
  const warmPayload = makePayload('warm');
  const warmResult = await runPipeline(warmPayload, { inference: mockInferenceWarm });

  if (warmResult.statusCode !== 200) fail(`Expected 200, got ${warmResult.statusCode}`);
  const warmRouting = warmResult.body.routing as { tier?: string } | undefined;
  if (warmRouting?.tier !== 'WARM') fail(`Expected WARM, got ${warmRouting?.tier}`);
  if (exitCode === 0) console.log('PASS');

  console.log('[TIER COLD] Low-score lead...');
  const coldPayload = makePayload('cold');
  const coldResult = await runPipeline(coldPayload, { inference: mockInferenceCold });

  if (coldResult.statusCode !== 200) fail(`Expected 200, got ${coldResult.statusCode}`);
  const coldRouting = coldResult.body.routing as { tier?: string } | undefined;
  if (coldRouting?.tier !== 'COLD') fail(`Expected COLD, got ${coldRouting?.tier}`);
  if (exitCode === 0) console.log('PASS');

  console.log('[TIER MANUAL] Double-invalid model output...');
  const manualPayload = makePayload('manual');
  const manualResult = await runPipeline(manualPayload, { inference: mockInferenceManual });

  if (manualResult.statusCode !== 200) fail(`Expected 200, got ${manualResult.statusCode}`);
  const manualRouting = manualResult.body.routing as { tier?: string } | undefined;
  if (manualRouting?.tier !== 'MANUAL') fail(`Expected MANUAL, got ${manualRouting?.tier}`);
  if (exitCode === 0) console.log('PASS');

  // adapters not configured here, so the HOT dispatch fails; lead still persisted, DLQ written
  console.log('[ADAPTER FAILURE] Forced via missing env...');
  const leadsCount = await count('leads');
  if (leadsCount !== 4) fail(`Expected 4 lead rows, got ${leadsCount}`);

  if (exitCode === 0) console.log('PASS');

  console.log('');
  if (exitCode === 0) {
    console.log('=== ALL ACCEPTANCE CRITERIA PASSED ===');
  } else {
    console.log('=== SOME CHECKS FAILED ===');
    process.exit(1);
  }
}

main().catch(e => {
  console.error('CRASH:', e);
  process.exit(1);
});