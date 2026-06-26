# Intake-to-Outbound Intelligence Pipeline

A lead-intelligence pipeline that receives a public form submission, enriches it with web research and a single contained language-model inference, scores it with deterministic rules, and routes it to one of three outbound tiers.

## Model Switch Notice

The pipeline previously used **Claude Haiku 3.5** for structured JSON enrichment. Anthropic retired that model on **2026-02-19**, which caused every inference call to fail and dead-lettered all leads to the `MANUAL` tier. We have switched the inference stage to **`google/gemma-4-26B-A4B-it`** served via **DeepInfra's OpenAI-compatible endpoint**. The pipeline is functional again.

## Architecture

```
[1] Webhook -> [2] HMAC/Normalize -> [3] Dedupe Guard
                                        |
[4] Web Research (fail-open) -> [5] Contained Inference (DeepInfra, `google/gemma-4-26B-A4B-it`, temp 0)
                                        |
                         [6] Validation Gate (AJV + one repair)
                                        |
                         [7] Scoring (pure fn, 0-100)
                                        |
                         [8] Router (HOT/WARM/COLD/MANUAL)
                                        |
                         [9] Persistence (leads + inference_audit)
```

## Quick Start (Local)

```bash
cp .env.example .env
# edit .env with your DATABASE_URL, INFERENCE_API_KEY, SEARCH_API_KEY, WEBHOOK_SECRET

npm install
npm run migrate                # apply Postgres migrations
npm test                       # run all unit tests
npm run validate:schemas       # validate JSON schemas
npm run smoke                  # end-to-end acceptance test
npm run eval                   # run eval suite locally (requires live API keys)
npm start                      # start HTTP server on PORT (default 3001)
```

## Deployment (Hetzner VPS)

This project is designed to run on a persistent Linux VPS with **systemd**. Secrets stay on the server only — nothing sensitive is committed to GitHub.

### Pipeline flow (production)

```
Tally form -> POST /intake-webhook -> google/gemma-4-26B-A4B-it via DeepInfra (structured JSON)
  -> Brave Search (web enrichment) -> composite scoring -> route:
       HOT  -> Slack + HubSpot CRM
       WARM -> Google Sheets
       COLD -> Postgres log only
```

### First-time VPS setup

SSH into your VPS, then run:

```bash
curl -fsSL https://raw.githubusercontent.com/jakemorganlabs/intake-n-outbound.pipeline/main/scripts/setup-vps.sh -o setup-vps.sh
bash setup-vps.sh
```

Or clone the repo and run the script from inside it:

```bash
git clone https://github.com/jakemorganlabs/intake-n-outbound.pipeline.git ~/intake-pipeline
cd ~/intake-pipeline
bash scripts/setup-vps.sh
```

The setup script will:

1. Install Node.js 22 and PostgreSQL (if missing)
2. Clone/pull the repo and run `npm ci` + migrations
3. **Prompt you one key at a time** for each secret (with a description of what it is for)
4. Write secrets to `.env` on the VPS (chmod 600, gitignored)
5. Install and start the `intake-pipeline` systemd service

### Deploy updates

From your laptop (SSH host is never stored in the repo):

```bash
VPS_HOST=user@your-vps-ip bash scripts/deploy.sh
```

This pulls latest `main`, runs migrations, and restarts the service.

### Service management

```bash
sudo systemctl status intake-pipeline
sudo journalctl -u intake-pipeline -f
curl http://localhost:3001/health
```

Point your Tally webhook to `POST https://<your-domain-or-ip>/intake-webhook` (use nginx or a reverse proxy for HTTPS in production).

### CI (GitHub Actions)

GitHub Actions runs **offline checks only** — lint, schema validation, unit tests, and migrations. No API keys are stored in GitHub. Live evals (`npm run eval`) are run locally on the VPS when you choose.

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
| `scripts/setup-vps.sh` | Interactive VPS installer + API key prompts |
| `scripts/deploy.sh` | Pull latest code and restart on VPS |
| `scripts/pipeline.service` | systemd unit file template |
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
- CI workflows (GitHub Actions): offline lint, schema validation, unit tests, and migrations on push — no secrets required.
- Eval suite: 33 fixtures across 7 categories (schema, routing, idempotency, degradation, injection, gibberish, multilingual).
- Sample report: `docs/sample_eval_report.md`.

## Pipeline Stages

- Postgres + n8n installed and running.
- `src/pipeline.ts`: full 9-stage pipeline with typed interfaces and pure/deterministic stages.
- HMAC verification with timing-safe comparison.
- Dedupe guard: atomic insert-if-absent, short-circuits duplicates with 200.
- Research adapter: Brave Search HTTP call with provenance, fail-open on any error.
- Contained inference: DeepInfra OpenAI-compatible endpoint (`google/gemma-4-26B-A4B-it`, `temperature: 0`, `response_format: json_object`), token and latency capture.
- Validation gate: strict JSON Schema via AJV draft-2020-12, one repair attempt with safe heuristics, MANUAL on double failure.
- Scoring and routing wired from core modules with no duplication.
- Persistence: `leads` + `inference_audit` INSERT with ON CONFLICT UPDATE, always runs even on MANUAL.
- HTTP server (`src/server.ts`): `POST /intake-webhook` and `GET /health`.
- Smoke tests (`scripts/smoke.ts` and `smoke.sh`): acceptance criteria covering worked example, duplicate handling, schema repair, double failure, and degraded search.
