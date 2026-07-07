# Makefile — MICT-PIPE-001 S05 deployment helpers
# Targets are thin wrappers around real commands, documented here so the runbook stays single-source.

.PHONY: hooks gate up down logs migrate backup restore-test smoke eval-prod lint test

# Symlink pre-commit hook into .git/hooks/
hooks:
	@echo "Linking scripts/hooks/pre-commit -> .git/hooks/pre-commit"
	@ln -sf $(PWD)/scripts/hooks/pre-commit .git/hooks/pre-commit

# Secret gate — run this before every commit
gate:
	@bash scripts/secret_gate.sh

# Bring up the production compose stack (from deploy/)
up:
	cd deploy && docker compose -f docker-compose.yml up -d

# Tear down the production compose stack
down:
	cd deploy && docker compose -f docker-compose.yml down

# Tail logs
logs:
	cd deploy && docker compose -f docker-compose.yml logs -f --tail=50

# Apply migrations against the running stack (via postgres container on compose network)
migrate:
	cd deploy && docker compose -f docker-compose.yml exec -T postgres psql -U $$POSTGRES_USER -d $$POSTGRES_DB -f /var/lib/postgresql/data/migrations/001_dedupe.sql || true
	@echo "Migrate target implemented in src/db/migrate.ts; run it with:"
	@echo "  cd deploy && source .env.production && npx tsx ../src/db/migrate.ts"

# Run nightly backup script
backup:
	bash deploy/cron/pg_dump.sh

# Run restore test into scratch container
restore-test:
	bash deploy/restore.sh

# External smoke test against production URL
smoke:
	bash scripts/smoke_prod.sh

# Eval suite against production (EVAL_ENV=prod)
eval-prod:
	EVAL_ENV=prod DATABASE_URL=$${DATABASE_URL} $(if $(shell command -v npx),npx tsx) evals/run.ts

# CI-style offline checks
lint:
	npm run lint

test:
	npm test
