# Production Runbook

Operator reference. Commands are exact.

## 1. Architecture

```
Internet -> Cloudflare Tunnel -> cloudflared -> n8n:5678 (127.0.0.1 only)
                                        |
                                        -> postgres:5432 (compose network only)
```

The tunnel exposes only `https://intake.jakemorganlabs.dev/webhook`. The n8n editor (`/`) and the database have no public route.

## 2. Redeploy

```bash
# SSH into the VPS, then:
cd /opt/intake-pipeline
git fetch origin
git pull --ff-only
cd deploy
docker compose -f docker-compose.yml up -d
```

Restarts services whose images changed. Postgres data persists in the named volume.

## 3. Migrate

Migrations live in `migrations/`. Apply against the running Postgres container:

```bash
cd /opt/intake-pipeline/deploy
source .env.production
docker compose -f docker-compose.yml exec -T postgres \
  psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -f /var/lib/postgresql/data/migrations/001_dedupe.sql
# ...repeat for 002 .. 006
```

If the Node build is on the VPS, the migration runner applies them in order:

```bash
cd /opt/intake-pipeline
source deploy/.env.production
npx tsx src/db/migrate.ts
```

## 4. Rotate a Secret

1. Edit `/opt/intake-pipeline/deploy/.env.production`.
2. Recreate the affected containers:

```bash
cd /opt/intake-pipeline/deploy
docker compose -f docker-compose.yml up -d --force-recreate n8n cloudflared
```

3. Update any external clients that use the old secret (e.g. the Tally form webhook secret).

## 5. Restore from Backup

1. Verify the backup with a tested restore into a scratch container:

```bash
cd /opt/intake-pipeline
bash deploy/restore.sh
```

2. If `restore.sh` reports PASS, restore into the live database:

```bash
cd /opt/intake-pipeline/deploy
source .env.production
LATEST=$(find ../backups -maxdepth 1 -name '*.dump' | sort -r | head -n 1)
docker compose -f docker-compose.yml exec -T postgres \
  pg_restore -U "$POSTGRES_USER" -d "$POSTGRES_DB" --no-owner --clean < "$LATEST"
```

3. Restart n8n to clear cached state:

```bash
cd /opt/intake-pipeline/deploy
docker compose -f docker-compose.yml restart n8n
```

## 6. Tunnel Ingress

Ingress rules live in the Cloudflare dashboard (`Zero Trust > Networks > Tunnels`):

- Public hostname: `intake.jakemorganlabs.dev`
- Service: `http://n8n:5678`
- Path filter: `/webhook*` only
- Default: 404 for everything else

Inspect from the VPS:

```bash
cd /opt/intake-pipeline/deploy
docker compose -f docker-compose.yml logs -f cloudflared
```

## 7. Backup Monitoring

Cron runs the dump at `15 3 * * *`.

```bash
tail -n 20 /opt/intake-pipeline/backups/backup.log
```

## 8. Closeout Commit

After deployment and verification, commit evidence to a branch:

```bash
git checkout -b closeout-evidence
# Drop into docs/evidence/:
#   eval_report_prod.md
#   smoke_prod_output.txt
#   sample_lead_row.md
#   nmap_posture.txt
bash scripts/secret_gate.sh
git add docs/evidence/ README.md && git commit -m "closeout: prod evals green, external smoke, posture proof"
git push -u origin closeout-evidence
```

Commit only what was actually observed. No fabricated data.