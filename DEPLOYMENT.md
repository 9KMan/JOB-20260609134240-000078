# Deployment Guide

Clean-Supabase-project deployment for the Multi-Tenant Manufacturing
Operations Platform foundation.

## Prerequisites

- A Supabase project (free or paid tier)
- Supabase CLI ≥ 1.180 (`brew install supabase/tap/supabase` or
  <https://github.com/supabase/cli>)
- `psql` ≥ 14 (for running the test SQL)
- Deno ≥ 1.40 (only if you want to run the function unit tests)
- The project's `service_role` key (admin only; never expose to clients)

## Environment

Copy `.env.example` to `.env` and fill in the values from your Supabase
project's API settings:

```bash
cp .env.example .env
```

Required:

| Variable | Source |
| --- | --- |
| `SUPABASE_URL` | Project Settings → API → Project URL |
| `SUPABASE_ANON_KEY` | Project Settings → API → Project API keys → `anon` |
| `SUPABASE_SERVICE_ROLE_KEY` | Project Settings → API → Project API keys → `service_role` |
| `DATABASE_URL` | Project Settings → Database → Connection string → Transaction pooler |

## 1. Link the project

```bash
supabase login
supabase link --project-ref <your-project-ref>
```

`<your-project-ref>` is the slug in your Supabase dashboard URL.

## 2. Apply migrations

```bash
supabase db push
```

This applies all 11 migrations in order:

1. `001_extensions_and_enums.sql` — required PostgreSQL extensions and
   enumerated types.
2. `002_organisations_and_users.sql` — tenancy, profiles, memberships.
3. `003_catalog.sql` — products, ingredients, recipes, recipe lines.
4. `004_ingredients_and_lots.sql` — facilities, suppliers, lots, prices.
5. `005_costing_and_pricing.sql` — cost pools, labour, pricing, retail.
6. `006_quality_and_compliance.sql` — events, CAPAs, mock recalls.
7. `007_engines_and_integrations.sql` — assessment, verification, integrations.
8. `008_production_and_event_log.sql` — batches, batch costs, system log.
9. `009_rls_policies.sql` — RLS on every table.
10. `010_sample_data.sql` — opt-in sample data (skipped by default).
11. `011_onboarding_save_atomic.sql` — atomic save function.

If the run fails on a migration, fix the issue and re-run. Migrations
use `if not exists` for additive changes where possible, but schema
corrections require a fresh DB.

## 3. Deploy the Edge Function

```bash
supabase functions deploy onboarding-save --no-verify-jwt
```

The function uses the service role internally; the `--no-verify-jwt`
flag is correct for service-to-service calls. The function URL is:

```
https://<project-ref>.supabase.co/functions/v1/onboarding-save
```

## 4. Set function secrets

In the Supabase dashboard: **Project Settings → Edge Functions →
Manage secrets**, add:

- `SUPABASE_URL` (= `https://<project-ref>.supabase.co`)
- `SUPABASE_SERVICE_ROLE_KEY`

The Edge Function reads these from the environment at startup.

## 5. Run the test suite

```bash
export DATABASE_URL="postgres://postgres:<password>@<host>:6543/postgres"

psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f tests/test_onboarding_save_handler.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f tests/test_rollback.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f tests/test_rls_isolation.sql
```

Optional Deno tests for the validator:

```bash
deno test -A supabase/functions/onboarding-save/tests/
```

## 6. Smoke test the Edge Function

```bash
curl -i -X POST "$SUPABASE_URL/functions/v1/onboarding-save" \
  -H "Authorization: Bearer $SUPABASE_SERVICE_ROLE_KEY" \
  -H "Content-Type: application/json" \
  --data @tests/fixtures/onboarding_sample.json
```

The first fixture you write should match `types.ts` exactly.

## Acceptance criteria

Per `SPEC.md` §11:

- All schema objects deploy successfully (no errors, all constraints honored) — verified by `supabase db push` exit code 0.
- All indexes deploy successfully — verified by the same run.
- RLS passes multi-tenant isolation tests — `tests/test_rls_isolation.sql`.
- Save-handler Edge Function passes validation tests — `supabase/functions/onboarding-save/tests/validation_test.ts`.
- Save-handler Edge Function passes full rollback tests — `tests/test_rollback.sql`.
- Sample onboarding payload creates complete supplier records in a single transaction — `tests/test_onboarding_save_handler.sql`.
- Deployment scripts run cleanly in fresh Supabase project — this document.
- Source code in public GitHub repo — push via `git push origin main`.

## Rollback

Migrations are not auto-reversible. To roll back, restore from a
project snapshot (Supabase → Project Settings → Database → Backups).
Apply destructive changes as new, forward-only migrations.
