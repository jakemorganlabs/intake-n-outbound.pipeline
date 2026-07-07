# Sample Lead Row (Synthetic)

__AFTER_DEPLOY__: paste a redacted/synthetic lead row from the production Postgres here. Do not include real PII.

```sql
-- Example structure (synthetic data):
SELECT lead_id, routing->>'tier', score->>'composite', created_at, status
FROM leads
WHERE idempotency_key LIKE 'smoke%'
ORDER BY created_at DESC
LIMIT 1;
```
