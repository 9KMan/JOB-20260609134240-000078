# Multi-Tenant Manufacturing Operations Platform — Phase 1 Foundation

Supabase-backed foundation for a multi-tenant platform serving food
manufacturers, exporters, and supply chain participants. This repository
implements the platform base layer and the SupplierOps onboarding
workflow as defined in `SPEC.md`. Future applications
(Export Readiness, Verified Supplier Registry, Export Coordination,
Fulfilment QC, Labelling Blueprint, Market Data Intelligence) build
on top of this foundation.

## Status

Phase 1 (Foundation) — complete. Implements:

- All schema objects from `SPEC.md` §4 (organisations, facilities, products,
  ingredients, recipes, cost pools, labour standards, pricing, retail
  commitments, ingredient lots, production batches, batch cost records,
  quality events, corrective actions, mock recalls, assessment engine,
  verification engine, shipment integrations, system event log, user roles).
- Soft-delete (`deleted_at`) and `updated_at` triggers on all tenant tables.
- Full row-level security (RLS) on every table, with `platform_admin`
  bypass and org-scoped policies for `org_owner` and `org_operator`.
- Atomic `onboarding_save_atomic` SQL function and the
  `onboarding-save` Supabase Edge Function (TypeScript / Deno).
- TypeScript validator for the wizard JSON contract.
- Test SQL for RLS isolation, save handler, rollback, and validation.
- Local Supabase dev stack via Docker Compose.

## Layout

```
.
├── SPEC.md                       # the authoritative spec for this phase
├── README.md                     # this file
├── DEPLOYMENT.md                 # fresh-project deployment walkthrough
├── docker-compose.yml            # local Supabase stack
├── .env.example                  # environment variables
├── supabase/
│   ├── config.toml               # Supabase CLI config
│   ├── migrations/               # numbered SQL migrations (001-011)
│   ├── functions/
│   │   └── onboarding-save/      # Deno Edge Function
│   │       ├── index.ts
│   │       ├── validation.ts
│   │       ├── types.ts
│   │       └── tests/validation_test.ts
│   └── tests/                    # reserved for future Supabase-local pgTAP tests
├── tests/                        # top-level test SQL files
│   ├── test_rls_isolation.sql
│   ├── test_onboarding_save_handler.sql
│   ├── test_rollback.sql
│   └── test_validation.sql
├── schema/
│   └── README.md                 # human-readable ERD summary
└── docs/                         # future architecture / decision records
```

## Quick start (local development)

Prerequisites: Docker, Supabase CLI, Deno (for the function tests only).

```bash
# 1. Boot the local Supabase stack
docker compose up -d

# 2. Apply migrations
supabase db reset

# 3. Run the integration tests
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f tests/test_onboarding_save_handler.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f tests/test_rollback.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f tests/test_rls_isolation.sql

# 4. Start the Edge Function
supabase functions serve onboarding-save

# 5. Run TypeScript validator unit tests (optional)
deno test -A supabase/functions/onboarding-save/tests/
```

## Production deployment

See [DEPLOYMENT.md](./DEPLOYMENT.md) for a clean Supabase project
walkthrough (`supabase link`, `supabase db push`,
`supabase functions deploy`).

## Design principles

The architecture, schema, security model, JSON contract, and event log
are **pre-specified** in `SPEC.md`. We implement them as-is — no
redesign. Five principles guide every table:

1. One living supplier record; never duplicate; update in place.
2. No hard deletion. Soft-delete via `deleted_at`.
3. Arrays only for display values. Use relational tables where integrity
   matters.
4. Operational records are factual; calculated records are versioned.
5. Organisation isolation is enforced at the RLS layer, not the
   application layer.

## Out of scope (Phase 1)

SupplierOps front-end, AI wizard UI, dashboards, reporting, mobile apps,
and the non-SupplierOps applications (Export Readiness, Registry, etc.).
