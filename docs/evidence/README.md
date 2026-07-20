# docs/evidence/

Artifacts that prove the pipeline is live and behaving as specified. All data here is synthetic or redacted. No real tokens, names, or internal URLs.

| File | What it is | Captured |
|------|-----------|----------|
| `eval_report_local.md` | local eval suite, all green | committed |
| `eval_report_prod.md` | `EVAL_ENV=prod` run against the live instance | __AFTER_DEPLOY__ |
| `smoke_prod_output.txt` | External smoke test transcript (Worked Example B in/out) | __AFTER_DEPLOY__ |
| `sample_lead_row.md` | Redacted synthetic lead row as stored in Postgres | __AFTER_DEPLOY__ |
| `nmap_posture.txt` | `nmap` scan showing zero open ports on the VPS public IP | __AFTER_DEPLOY__ |

These slots are filled on the `closeout-evidence` branch per `docs/runbook.md` section 8. Commit only what was observed; do not fabricate.