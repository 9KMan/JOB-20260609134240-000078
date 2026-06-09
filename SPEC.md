# Specification: Multi-Tenant Manufacturing Operations Platform — Phase 1 Foundation

## 1. Project Overview

**Project:** Senior Supabase Developer – Multi-Tenant Manufacturing Operations Platform
**GitHub:** https://github.com/9KMan/JOB-20260609134240-000078
**Lead:** https://www.upwork.com/jobs/~022064269464186343105
**Client:** Upwork
**Tier:** EXPERT
**Budget:** $10–50/hr
**Duration:** 1–3 months | <30 hrs/week

This is NOT a greenfield project. The platform architecture, relational schema, row-level security model, JSON onboarding contract, event logging model, and build sequence have already been fully specified. The developer implements the supplied architecture — no redesign.

The platform is the foundation for multiple applications: SupplierOps (manufacturing operations + traceability), Export Readiness Assessment, Verified Supplier Registry, Export Coordination, Fulfilment QC, Labelling Blueprint, and Market Data Intelligence. This project covers only the platform foundation and SupplierOps onboarding layer.

---

## 2. Technical Stack

`supabase` · `postgresql` · `row level security` · `supabase edge functions` · `typescript` · `api development` · `database design` · `backend development` · `software architecture` · `database architecture`

---

## 3. Design Principles (Pre-Specified — Implement As-Is)

1. **One living supplier record** — never duplicate; update in place
2. **No hard deletion** — soft-delete pattern across all tables
3. **Arrays only for display values** — use relational tables where integrity matters
4. **Operational records are factual; calculated records are versioned**
5. **Organisation isolation is non-negotiable** — enforced at the RLS layer, not application layer

---

## 4. Core Schema Domains (Pre-Designed — Deploy As-Specified)

All tables below are deployed via numbered migration files under `supabase/migrations/`.

### Platform Foundation
- `organisations` — tenant root, one per client
- `facilities` — physical sites per org (site, address, timezone)
- `users` — Supabase Auth, linked to organisations via `user_organisations` junction
- `user_roles` — enum: `platform_admin`, `org_owner`, `org_operator`

### SupplierOps — Product & Recipe
- `products` — finished goods (SKU, name, category, uom, status)
- `ingredients` — raw materials (code, name, category, uom, allergen flags)
- `ingredient_price_history` — time-series pricing per supplier
- `raw_material_suppliers` — supplier entity per org
- `recipe_versions` — versioned recipes (product FK, version number, status)
- `recipe_ingredients` — ingredient lines per recipe version (qty, unit, cost_pct)

### Costing & Pricing
- `cost_pools` — cost categories (material, labour, overhead, yield)
- `labour_standards` — rate tables per facility/role
- `pricing_configurations` — pricing rules per product/channel
- `pricing_configuration_history` — audit trail of pricing changes
- `retail_commitments` — agreed retail prices per product/customer

### Operations & Traceability
- `ingredient_lots` — lot tracking per ingredient (supplier, received date, expiry)
- `production_batches` — batch records (facility, product, quantity, yield, status)
- `batch_cost_records` — cost breakdown per batch (links cost pools)

### Quality & Compliance
- `quality_events` — QC checks and deviations
- `corrective_actions` — CAPA records linked to quality events
- `mock_recalls` — recall drill records

### Engines
- `assessment_engine` — scoring bands and assessment criteria
- `verification_engine` — verification status tracking

### Integration
- `shipment_integrations` — external system hooks

### Platform Services
- `system_event_log` — platform-level audit of significant state changes
  - Events: `assessment_band_changed`, `verification_status_changed`, `recipe_version_activated`, `maturity_level_changed`, `onboarding_completed`, `seasonal_profile_recalibrated`

---

## 5. Security Model (Pre-Designed — Implement As-Specified)

**Multi-tenant isolation via organisation-level Row-Level Security (RLS).**

All tables include `organisation_id` as the tenant discriminator. RLS policies enforce:
- Users can only read/write rows where `organisation_id` matches their active org membership
- `platform_admin` role bypasses org-level filtering (platform-wide read)
- `org_owner` and `org_operator` are scoped to their organisation

**RLS must be implemented on ALL tables** — no exceptions. This is the primary acceptance criterion.

---

## 6. Wizard Onboarding Contract (Pre-Designed)

An AI onboarding wizard produces a structured JSON payload. The payload contains:
- Organisation + facility setup
- Products, ingredients, recipes
- Cost pools, labour standards
- Pricing configuration
- Retail commitments

**Save Handler (Edge Function):**
- Validates all cross-references in the JSON payload
- Writes the complete onboarding dataset as a **single PostgreSQL transaction**
- Full rollback on any validation failure
- Returns detailed error messages per failed constraint
- Transaction must be atomic — no partial writes

---

## 7. System Event Logging

Platform-level `system_event_log` table records significant decisions and state changes. Written **only** through application services and Edge Functions — never directly by clients.

Event types: `assessment_band_changed`, `verification_status_changed`, `recipe_version_activated`, `maturity_level_changed`, `onboarding_completed`, `seasonal_profile_recalibrated`.

---

## 8. Index Strategy

Indexes on:
- All foreign keys (organisation_id, facility_id, product_id, etc.)
- High-cardinality columns used in WHERE clauses
- Composite indexes for common query patterns (e.g., `facility_id + status`, `organisation_id + product_id`)
- Partial indexes for soft-deleted records

---

## 9. Project Structure

```
supabase/
  migrations/
    001_extensions_and_enums.sql
    002_organisations_and_users.sql
    003_products_and_recipes.sql
    004_ingredients_and_lots.sql
    005_costing_and_pricing.sql
    006_quality_and_compliance.sql
    007_engines_and_integrations.sql
    008_system_event_log.sql
    009_rls_policies.sql
    010_sample_data.sql
  functions/
    onboarding-save-handler/
      index.ts
      validation.ts
      types.ts
      tests/
  supabase-config.toml
  .env.example
schema/
  README.md
tests/
  test_rls_isolation.sql
  test_onboarding_save_handler.sql
  test_rollback.sql
  test_validation.sql
README.md
DEPLOYMENT.md
docker-compose.yml
.gitignore
```

---

## 10. Out of Scope

- SupplierOps front-end interface
- AI Wizard interface / Claude API / LLM integration
- Dashboard development
- Reporting screens
- Export Readiness / Registry / Fulfilment QC / Export Coordination applications
- HACCP application
- Mobile applications
- Public website development

---

## 11. Acceptance Criteria

- [ ] All schema objects deploy successfully (no errors, all constraints honored)
- [ ] All indexes deploy successfully
- [ ] RLS passes multi-tenant isolation tests (org A cannot read/write org B's data)
- [ ] Save-handler Edge Function passes validation tests
- [ ] Save-handler Edge Function passes full rollback tests (failed validation → zero rows written)
- [ ] Sample onboarding payload creates complete supplier records in a single transaction
- [ ] Deployment scripts run cleanly in fresh Supabase project
- [ ] Source code in public GitHub repo

---

## 12. Technical Notes

- Use Supabase migrations (`supabase migrations push`) for schema deployment
- Edge Functions written in TypeScript, deployed via `supabase functions deploy`
- RLS policies use `auth.uid()` + `auth.jwt()` to identify org membership
- Use `ENABLE ROW LEVEL SECURITY` on all tables; set default deny
- PostgreSQL transaction with `SAVEPOINT` for rollback testing
- Supabase `pg_net` extension for any outbound webhook calls