# Intake-to-Outbound Intelligence Pipeline — SRS & TDD

**Doc ID:** MICT-PIPE-001
**Version:** 1.1 — As built
**Author:** Jake Morgan
**Status:** Deployed. Live at `https://intake.jakemorganlabs.dev`.

> The model proposes structure. Deterministic code disposes.

---

## Revision record

| Rev | Date | Status | Summary |
|---|---|---|---|
| 1.0 | Baseline | Approved for build | Full SRS/TDD. Runtime and providers specified generically. |
| 1.1 | As built | Deployed | Runtime, model, and outbound adapters pinned to the deployed system. See the change log below. |

### Changes from Rev 1.0

1. **§2.4, §8.3, §19 — Runtime.** Rev 1.0 specified a containerized workflow runtime with Postgres as a sibling container. The deployed system is a TypeScript service (Hono) run directly by systemd. There is no workflow engine in the runtime path. The `workflows/` directory holds reference exports only.
2. **§8.3 — Inference provider.** Rev 1.0 said "hosted small language model." The deployed model is `google/gemma-4-26B-A4B-it` on DeepInfra. Temperature is 0. The model ID is recorded on every lead.
3. **§8.3 — Search provider.** The web-research adapter calls the Brave Search API.
4. **§5.4–5.6 — Outbound adapters.** The Sheets adapter authenticates with a Google service account and `google-auth-library`, not an API key. The CRM adapter writes a custom `lead_source` property. It does not write `notes_last_updated` (read-only in HubSpot) or `hs_external_id` (not a real property).
5. **§5.1 — Intake adapter.** An adapter flattens the Tally `data.fields[]` array into the canonical `{name, email, message}` shape before validation.
6. **§19 — Edge.** The tunnel connector runs as one standalone host service, not as a per-app sidecar container. Cloudflare manages the tunnel from the dashboard. The public path is `/intake-webhook` on `intake.jakemorganlabs.dev`.
7. **§18 — Test posture.** The unit suite runs keyless and passes 47 of 47. The eval suite holds 33 labeled cases across seven categories and gates `main` in CI.

---

## §1 Purpose and scope

This document specifies and records the design of a lead-intelligence pipeline. One webhook submission goes in. A scored, tiered outbound action comes out.

The pipeline gives the model exactly one job: a single structured extraction per lead. A JSON Schema gate validates the output before any downstream stage reads it. Deterministic code does the scoring, the routing, and every outbound write.

## §2 System overview

1. A form submission arrives at the public webhook.
2. The idempotency guard derives a stable key and drops duplicates.
3. The research collector runs one bounded web query.
4. The inference unit makes one structured call to the model.
5. The validation gate checks the output against the schema.
6. The scoring engine computes a deterministic composite score.
7. The router assigns a tier and fires the matching adapter.

Tiers:

- **HOT** — Slack alert and a CRM contact.
- **WARM** — a row in a shared spreadsheet for batch follow-up.
- **COLD** — a database log entry only.
- **MANUAL** — the safe path. Any schema failure routes here with the raw payload preserved.

**NOTE:** The prompt is an optimization. The validation gate is the guarantee. The system depends on the guarantee.

## §3 Functional requirements (summary)

| ID | Requirement |
|---|---|
| FR-IN | The webhook must accept, normalize, and persist each submission. |
| FR-DD | The pipeline must derive an idempotency key and must process each lead at most once. |
| FR-RS | The research collector may run one bounded search per lead. A search failure must degrade, not block. |
| FR-AI | The model must return one schema-valid object per lead. One repair call is permitted. A second failure routes the lead to MANUAL. |
| FR-SC | Scoring must be deterministic. The same input must give the same score. |
| FR-RT | The router must map score bands to tiers with externalized thresholds. |
| FR-AU | Every inference call must be audited with the pinned model ID, tokens, and latency. |

## §8 Architecture as built

### 8.3 Technology stack

| Layer | As built |
|---|---|
| Service | TypeScript, Hono HTTP server, `src/pipeline.ts` nine-stage spine. Run with `tsx`. No build step. |
| Process manager | systemd unit `intake-pipeline`. Restart on failure. |
| Inference | `google/gemma-4-26B-A4B-it` on DeepInfra. Forced structured output. Temperature 0. Pinned and recorded per lead. |
| Research | Brave Search API behind a swappable adapter. |
| State | Host Postgres. Tables for dedupe, leads, inference audit, and dead letters. Six SQL migrations. |
| Outbound | Slack webhook, HubSpot API, Google Sheets with a service account. Each behind an adapter. |
| Edge | Cloudflare Tunnel. One public path: `/intake-webhook`. No open inbound ports. |

### §15 Inference configuration

1. One tool is defined. Its input schema is the enrichment contract.
2. `tool_choice` forces the model to call that tool. Free prose is not accepted.
3. The system instruction frames the model as a structured extractor. It must return null for a value the input does not support. It must treat text inside the lead message as data, never as instructions.
4. On a schema failure, the pipeline makes exactly one repair call. The repair call includes the validation error and the prior output.
5. A second failure is terminal. The lead routes to MANUAL.

## §16 Security

- The tunnel publishes one path. Everything else returns 404 at the edge.
- Secrets live on the server in `deploy/.env.production`. The file is not in git.
- `scripts/secret_gate.sh` scans the tree for token patterns before each commit.
- The service account key is a local file, ignored by git, referenced by path in the environment.

## §18 Evaluation

| Suite | Cases | Result |
|---|---|---|
| Unit tests (keyless, offline) | 47 | 47 pass |
| Eval suite: schema, routing, idempotency, degradation, injection, gibberish, multilingual | 33 | 33 pass, gates CI on `main` |

## §19 Deployment topology as built

```
Internet
   |
   v
Cloudflare Tunnel  (publishes /intake-webhook only)
   |
   v
Hetzner VPS
   systemd: intake-pipeline  ->  Hono service on :3001
   host Postgres (loopback)
   |
   v  outbound HTTPS only
DeepInfra · Brave · Slack · HubSpot · Google Sheets
```

**Redeploy procedure:**

1. Pull the branch on the server.
2. Run the migrations.
3. Restart the service: `sudo systemctl restart intake-pipeline`.

**WARNING:** There is no build step. An edit does nothing until you restart the service.

---

*Piece I of a five-piece portfolio. The capstone reuses this piece's contained intake extraction as its intake stage.*
