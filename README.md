# Intake-to-Outbound Intelligence Pipeline

A lead-intelligence pipeline that receives a public form submission, enriches it with web research and a single contained language-model inference, scores it with deterministic rules, and routes it to one of three outbound tiers.

## Architecture

```
[1] Webhook -> [2] HMAC/Normalize -> [3] Dedupe Guard
                                        |
[4] Web Research (fail-open) -> [5] Contained Inference (Anthropic, temp 0)
                                        |
                         [6] Validation Gate (AJV + one repair)
                                        |
                         [7] Scoring (pure fn, 0-100)
                                        |
                         [8] Router (HOT/WARM/COLD/MANUAL)
                                        |
                         [9] Persistence (leads + inference_audit)
```

## Quick Start

```bash
cp .env.example .env
# edit .env with your DATABASE_URL, MODEL_API_KEY, SEARCH_API_KEY, WEBHOOK_SECRET

npm install
npm run migrate                # apply Postgres migrations
npm test                       # run all unit tests
npm run validate:schemas       # validate JSON schemas
npm run smoke                  # end-to-end acceptance test
npm run eval                   # run eval suite (33 fixtures, 7 categories)
npm start                      # start HTTP server on PORT (default 3001)
```

## Key Files

| File | Purpose |
|---|---|
| `src/pipeline.ts` | Full orchestration spine - all stages wired |
| `src/server.ts` | Hono HTTP webhook receiver |
| `src/cli.ts` | CLI entry for stdin pipeline execution |
| `src/scoring.ts` | Deterministic 0-100 composite scoring |
| `src/router.ts` | Confidence-aware tier routing |
| `src/idempotency.ts` | Key derivation function |
| `schemas/inference_output.schema.json` | Strict JSON Schema gate for model output |
| `config/scoring.json` | Versioned weights and factors |
| `scripts/smoke.ts` | End-to-end acceptance test |
| `workflows/intake_main.json` | n8n workflow export |

## Design Principles

- **Containment**: The model is given one job: emit a structured object. Its output is checked against a strict schema before it is allowed to influence anything downstream.
- **Validation gate**: `additionalProperties: false`, enumerated values, bounded ranges. On failure: one repair, then MANUAL.
- **Fail-open research**: Web search timeout or error results in a degraded flag; pipeline continues.
- **Atomic dedupe**: `INSERT ... ON CONFLICT DO NOTHING` against `dedupe` table.
- **Audit trail**: Every model call writes a row with model id, tokens, latency, validation result, and repair_used flag.

## Core Components

- Four Postgres migrations: `dedupe`, `leads`, `inference_audit`, `dead_letter`.
- Two JSON Schema documents: `canonical_lead.schema.json`, `inference_output.schema.json`.
- `scoring.ts`: pure function computing 0-100 composite from validated signals, fully unit-tested.
- `router.ts`: pure function mapping (composite, confidence) to tier and actions, fully unit-tested.
- Versioned scoring config externalized.
- CI workflow (GitHub Actions) running tests, schema validation, and eval suite on push.
- Eval suite: 33 fixtures across 7 categories (schema, routing, idempotency, degradation, injection, gibberish, multilingual).
- Sample report: `docs/sample_eval_report.md`.

## Pipeline Stages

- Postgres + n8n installed and running.
- `src/pipeline.ts`: full 9-stage pipeline with typed interfaces and pure/deterministic stages.
- HMAC verification with timing-safe comparison.
- Dedupe guard: atomic insert-if-absent, short-circuits duplicates with 200.
- Research adapter: Brave Search HTTP call with provenance, fail-open on any error.
- Contained inference: Anthropic structured tool-use (claude-3-5-haiku-20241022, `temperature: 0`), token and latency capture.
- Validation gate: strict JSON Schema via AJV draft-2020-12, one repair attempt with safe heuristics, MANUAL on double failure.
- Scoring and routing wired from core modules with no duplication.
- Persistence: `leads` + `inference_audit` INSERT with ON CONFLICT UPDATE, always runs even on MANUAL.
- HTTP server (`src/server.ts`): `POST /intake-webhook` and `GET /health`.
- Smoke tests (`scripts/smoke.ts` and `smoke.sh`): acceptance criteria covering worked example, duplicate handling, schema repair, double failure, and degraded search.
