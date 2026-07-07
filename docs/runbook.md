# Production Runbook — MICT-PIPE-001

> One-page reference for operators. Every command is exact and copy-pasteable.

---

## 1. Architecture at a Glance

```
Internet -> Cloudflare Tunnel -> cloudflared -> n8n:5678 (127.0.0.1 only)
                                        |
                                        -> postgres:5432 (compose network only)
```

The tunnel exposes **only** `https://intake.jakemorganlabs.dev/webhook`. The n8n editor (`/`) and the database are unreachable from the public internet.

---

## 2. Redeploy

```bash
# SSH into the VPS, then:
cd /opt/intake-pipeline
git fetch origin
git pull --ff-only
cd deploy
docker compose -f docker-compose.yml up -d
```

This restarts services whose images changed. Postgres data persists in the named volume.

---

## 3. Migrate

The migrations are in `migrations/`. Apply them against the running Postgres container:

```bash
cd /opt/intake-pipeline/deploy
source .env.production
docker compose -f docker-compose.yml exec -T postgres \
  psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -f /var/lib/postgresql/data/migrations/001_dedupe.sql
docker compose -f docker-compose.yml exec -T postgres \
  psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -f /var/lib/postgresql/data/migrations/002_leads.sql
docker compose -f docker-compose.yml exec -T postgres \
  psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -f /var/lib/postgresql/data/migrations/003_inference_audit.sql
docker compose -f docker-compose.yml exec -T postgres \
  psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -f /var/lib/postgresql/data/migrations/004_dead_letter.sql
docker compose -f docker-compose.yml exec -T postgres \
  psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -f /var/lib/postgresql/data/migrations/005_counters.sql
docker compose -f docker-compose.yml exec -T postgres \
  psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -f /var/lib/postgresql/data/migrations/006_cost_tracking.sql
```

Or, if the Node server build is on the VPS:

```bash
cd /opt/intake-pipeline
source deploy/.env.production
npx tsx src/db/migrate.ts
```

---

## 4. Rotate a Secret

1. Edit the secret in `/opt/intake-pipeline/deploy/.env.production`.
2. Recreate the affected container(s):

```bash
cd /opt/intake-pipeline/deploy
docker compose -f docker-compose.yml up -d --force-recreate n8n cloudflared
```

3. Update any external clients (e.g. the Tally form webhook secret).

---

## 5. Restore from Backup

1. **Verify the backup** (tested restore into a scratch container):

```bash
cd /opt/intake-pipeline
bash deploy/restore.sh
```

2. If `restore.sh` reports PASS, restore into the **live** database:

```bash
cd /opt/intake-pipeline/deploy
source .env.production
LATEST=$(find ../backups -maxdepth 1 -name '*.dump' | sort -r | head -n 1)
docker compose -f docker-compose.yml exec -T postgres \
  pg_restore -U "$POSTGRES_USER" -d "$POSTGRES_DB" --no-owner --clean < "$LATEST"
```

3. Restart n8n to clear any cached state:

```bash
cd /opt/intake-pipeline/deploy
docker compose -f docker-compose.yml restart n8n
```

---

## 6. Tunnel Ingress (Cloudflare Dashboard)

The tunnel ingress rules live in the Cloudflare dashboard (`Zero Trust > Networks > Tunnels`):

- **Public hostname:** `intake.jakemorganlabs.dev`
- **Service:** `http://n8n:5678`
- **Path filter:** Only `/webhook*` is routed.
- **Default:** All other paths return `404`.

To inspect the tunnel from the VPS:

```bash
cd /opt/intake-pipeline/deploy
docker compose -f docker-compose.yml logs -f cloudflared
```

---

## 7. Backup Monitoring

Backups run via cron at `15 3 * * *`.

```bash
# Verify the last few backup lines:
tail -n 20 /opt/intake-pipeline/backups/backup.log
```

---

## 8. Closeout Commit Protocol

After deployment and verification, the operator commits evidence:

```bash
git checkout -b closeout-evidence
# Drop into docs/evidence/:
#   - eval_report_prod.md
#   - smoke_prod_output.txt
#   - sample_lead_row.md
#   - nmap_posture.txt
bash scripts/secret_gate.sh
git add docs/evidence/ README.md && git commit -m "closeout: production evidence -- prod evals green, external smoke, posture proof"
git push -u origin closeout-evidence
```
