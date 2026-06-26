# SESSION STATE

## Current State
- Task: Session S04 -- Evals & Observability (MICT-PIPE-001)
- Last checkpoint: [CKPT 4] Session S04 complete
- Branch: main
- Next step: S05 Deployment

## Session S04 Goal
- Create 30+ eval fixtures across 7 categories (schema, routing, idempotency, degradation, injection, gibberish, multilingual)
- Build eval runner (evals/run.ts) that posts fixtures to webhook, polls DB, asserts labels, exits 0/1
- Generate markdown report at evals/report.md on each run
- Wire CI gate (.github/workflows/evals.yml) spinning up stack and running suite
- Add structured JSON logging to every pipeline stage (execution_id, lead_id, stages, model_id, tokens, tier, status)
- Add Postgres counters (metrics_events) + metrics scripts (scripts/metrics.sh, scripts/cost_monthly.sh)
- Add cost tracking to inference_audit with monthly aggregation and price config
- Commit sample eval report to docs/ and update README link
- Run smoke tests + lint + schema validation, verify all pass before final checkpoint

## What Session 4 Produces
- `evals/fixtures/`: 33 labeled synthetic submissions across 7 categories, each with adjacent `.label.json`
- `evals/run.ts`: Eval runner with category filter, idempotency tracking across pairs, pass/fail with markdown report
- `evals/report.md`: Generated per-run; sample committed to `docs/sample_eval_report.md`
- `.github/workflows/evals.yml`: CI workflow that starts server, runs evals, uploads report artifact
- `src/logger.ts`: Structured log emission with execution_id, per-stage timings, token counts, tier, status
- `src/metrics.ts`: Simple counter inserts to `metrics_events` table
- `migrations/005_counters.sql`: metrics_events table + indexes
- `migrations/006_cost_tracking.sql`: cost_cents and price_snapshot on inference_audit
- `scripts/metrics.sh`: Bash metrics reporter (leads, tiers, inference health, DLQ, degraded)
- `scripts/cost_monthly.sh`: Monthly cost aggregation with price config warning
- `config/pricing.json`: Versioned price snapshot (model, rates, source, recorded_at)
- `docs/sample_eval_report.md`: Sample report for portfolio display
- README updated with `npm run eval` command and eval suite description

## Completed Steps
1. Fixtures: 33 fixtures + labels across 7 categories created and validated
2. Eval runner: TypeScript with DB polling, label assertions, idempotency tracking, report generation
3. CI gate: GitHub Actions workflow with postgres service, server startup, eval run, artifact upload
4. Structured logging: `logExecution` emits JSON-line logs from both happy-path and inference-failure paths in `runPipeline`
5. Counters: `metrics_events` table + `recordMetric` calls in pipeline for leads_total, leads_by_tier, search_degraded, repair_used, gate_failures_total, dlq_total
6. Cost tracking: per-call `cost_cents` computed from `config/pricing.json` and stored with `price_snapshot`
7. Sample report + README updated
8. All 47 unit tests pass. Smoke tests: 5/5 acceptance criteria pass. TypeScript: 0 compile errors.

## Remaining Before Handoff
- Session S05 (Deployment) can begin after commit: containerize stack, expose via encrypted tunnel, confirm evals still pass against deployed instance

## Checkpoint Log

### CKPT 1 -- Repo scaffold + deterministic core
- Initialized TypeScript project with Vitest, AJV, pg.
- Created .env.example, tsconfig.json, vitest.config.ts, .gitignore.
- Created directory structure: src/, schemas/, migrations/, config/, fixtures/, scripts/, .github/workflows/.
- Installed dependencies, green.

### CKPT 1 continued -- Postgres migrations
- Four migrations per Section 11.1: dedupe (001), leads (002), inference_audit (003), dead_letter (004).
- Indexed for fast lookups; partial indexes on status and resolved_at; dedupe key is PRIMARY KEY.
- Migration runner at `src/db/migrate.ts`, connection pool at `src/db/index.ts`.

### CKPT 1 continued -- JSON Schemas
- `schemas/inference_output.schema.json`: strict draft-2020-12, additionalProperties:false, bounded enums, confidence in [0,1].
- `schemas/canonical_lead.schema.json`: full lead record schema matching Section 11.1.
- Validation script at `scripts/validate-schemas.ts` -- compiles schemas with ajv/2020, no warnings.

### CKPT 1 continued -- Idempotency + Scoring + Router
- `src/idempotency.ts`: deriveIdempotencyKey with sub:/drv: prefixes, email normalization tested.
- `src/scoring.ts`: pure function computing 0-100 composite from validated signals.
- `src/router.ts`: pure function mapping (composite, confidence) -> tier + actions.
- Versioned config at `config/scoring.json` (schema_version, weights, factors).
- Worked Example B.4 fixture at `fixtures/worked-example-b4.json` producing composite = 96 exactly.
- Tests: 23 passed covering idempotency, scoring (B.4->96 exact), mixed/boundary cases, router (all four tiers + FR-RT-4 confidence cap + MANUAL).

### CKPT 1 continued -- CI
- `.github/workflows/test.yml`: lint, schema validation, unit tests, Postgres migration check on every push/PR.
- Green on local verification: `npm run lint` -> 0 errors; `npm run validate:schemas` -> OK; `npm test` -> 23 passed.

### CKPT 2 -- Session S02 complete
- Installed n8n (v2.25.7) native via npm, configured with Postgres backend, owner account created on localhost:5678.
- Installed PostgreSQL 16 via Homebrew, started service, created `intake_pipeline` and `n8n` databases, ran all 4 migrations.
- `src/pipeline.ts`: complete orchestration spine -- HMAC + normalizer, idempotency guard (atomic INSERT ON CONFLICT), research adapter (fail-open, provenance), contained inference (DeepInfra OpenAI-compatible endpoint with `google/gemma-4-26B-A4B-it`, `response_format: json_object`, temp 0, token/latency capture), validation gate (AJV strict JSON Schema + one-shot repair + MANUAL fallback), scoring (versioned config, 0-100 composite), router (confidence-aware tiering), persistence (INSERT leads + inference_audit, always runs even on MANUAL).
- `src/server.ts`: Hono HTTP webhook entrypoint at `/intake-webhook` + health check.
- `src/cli.ts`: CLI reads JSON payload from stdin, runs pipeline, prints structured result.
- `workflows/intake_main.json`: n8n workflow JSON export with all pipeline nodes (webhook -> HMAC -> dedupe -> research -> inference -> gate -> scoring -> router -> persist -> response).
- `scripts/smoke.ts` + `scripts/smoke.sh`: end-to-end acceptance tests covering AC-1 (worked example B -> composite 96, tier HOT), AC-2 (duplicate -> idempotent), AC-3 (schema-invalid -> 1 repair -> succeeds), AC-4 (double-invalid -> MANUAL persisted), AC-5 (search unavailable -> degraded but completes), NFR-PE-1 (p95 latency under 30s -- measured 19ms over 20 runs).
- TypeScript: 0 compile errors. Tests: 44 passed (23 S01 + 21 S02). Smoke: 5/5 acceptance criteria passing.
- `.env.example` updated with S02 env vars: MODEL_API_KEY, MODEL_ID, SEARCH_API_KEY, PORT.
- `package.json` updated: version 1.0.1, description S02, added scripts `start`, `smoke`, `pipeline`.

### CKPT 3 -- Session S03 complete
- `src/adapters/chat.ts`: Slack incoming-webhook adapter with retry + provenance logging.
- `src/adapters/crm.ts`: HubSpot contact create adapter with dedupe key as `hs_external_id` and retry.
- `src/adapters/sheet.ts`: Google Sheets append adapter (service-account path) with retry.
- `src/adapters/retry.ts`: Shared `withRetry` utility (3 attempts, 2s/4s/8s backoff, retryable HTTP detection).
- `src/adapters/dlq.ts`: Dead-letter writer using `pool` for INSERT with lead snapshot + stage + error.
- `src/adapters/index.ts`: Re-export hub for all adapters and DLQ.
- Adapter unit tests: chat, CRM, sheet each verify `ok=false` and descriptive error when env vars missing.
- `src/pipeline.ts` updated:
  - `router()` now uses inline object arg to match `router.test.ts` and `router.ts`.
  - `runPipeline()` persists FIRST, then dispatches adapters per tier (HOT chat+CRM, WARM sheet, COLD none).
  - MANUAL/inference_failed persists, writes DLQ, fires chat alert.
  - Adapter failure writes DLQ, updates lead status, fires alert; lead record still present.
- `src/pipeline.test.ts`: Updated router calls to use object-argument API.
- `scripts/smoke-s03.ts`: End-to-end smoke covering HOT, WARM, COLD, MANUAL, and adapter failure invariants.
- `scripts/smoke.sh` updated: tier-mode selector, `chaos` mode forces adapter failure and verifies DLQ + lead persistence.
- `workflows/intake_error.json`: n8n error-workflow with snapshot, DLQ writer, and Slack alert.
- `.env.example` updated: SLACK_WEBHOOK_URL, HUBSPOT_API_KEY, GOOGLE_SHEETS_API_KEY, GOOGLE_SHEET_ID, GOOGLE_SHEET_RANGE.
- TypeScript: 0 compile errors. Tests: 47 passed (44 S01+S02 + 3 adapter unit tests). Smoke: 5/5 passed.

### CKPT 4 -- Session S04 complete
- `evals/run.ts`: Eval runner. Posts fixtures to local webhook, polls DB, asserts against labels, generates markdown report.
- `evals/fixtures/`: 33 labeled synthetic submissions across 7 categories.
- `.github/workflows/evals.yml`: CI gate spinning up stack and running eval suite on every push.
- `src/logger.ts`: Structured JSON logging with execution_id, per-stage timings, model_id, token counts, tier, status.
- `src/metrics.ts`: Counter inserts to `metrics_events` for leads_total, leads_by_tier, search_degraded, repair_used, gate_failures_total, dlq_total.
- `migrations/005_counters.sql` + `006_cost_tracking.sql`: metrics_events table and cost_cents/price_snapshot on inference_audit.
- `config/pricing.json`: Versioned price config with warning threshold.
- `scripts/metrics.sh` + `scripts/cost_monthly.sh`: Metrics and cost aggregation scripts.
- `docs/sample_eval_report.md`: Sample report for portfolio display.
- README updated with `npm run eval` and eval suite description.
- Verification: 47 unit tests passed. Smoke: 5/5 passed. TypeScript: 0 compile errors.
