# Schema Overview

Plain-English summary of the Phase 1 schema. The authoritative source
for every column is the SQL in `../supabase/migrations/`.

## Tenancy

- `organisations` — tenant root. Every row in every other table belongs
  to an organisation via `organisation_id`.
- `facilities` — physical sites owned by an organisation.
- `profiles` — 1-to-1 mirror of `auth.users`.
- `organisation_members` — user ↔ organisation membership with a role.
- `organisation_invites` — pending invitations.
- `user_roles` — cross-cutting platform roles (`platform_admin`,
  `org_owner`, `org_operator`).

## Catalog & Recipes

- `products` — finished goods (SKU, name, category, unit of measure).
- `ingredients` — raw materials (SKU, name, allergens).
- `recipes` — versioned formulations per product.
- `recipe_ingredients` — ingredient lines per recipe version.

## Supply & Traceability

- `raw_material_suppliers` — suppliers per organisation.
- `ingredient_lots` — lot tracking (supplier, received date, expiry,
  quantity remaining, lot status).
- `ingredient_price_history` — time-series pricing per supplier/ingredient.
- `production_batches` — batch records (facility, product, recipe,
  planned vs. actual quantity, yield %, status).
- `batch_cost_records` — cost breakdown per batch, linking to cost pools.

## Costing & Pricing

- `cost_pools` — material, labour, overhead, yield.
- `labour_standards` — rate tables per facility/role.
- `pricing_configurations` — pricing rules per product/channel.
- `pricing_configuration_history` — audit trail of pricing changes.
- `retail_commitments` — agreed retail prices per product/customer.

## Quality & Compliance

- `quality_events` — QC checks, deviations, complaints, releases,
  rejections, spec checks.
- `corrective_actions` — CAPAs linked to quality events.
- `mock_recalls` — recall drill records with traceability scoring.

## Engines & Integrations

- `assessment_engine` — scoring bands and assessment criteria.
- `verification_engine` — verification status tracking per subject.
- `shipment_integrations` — external system hooks (provider, direction,
  status, last error).

## Platform Services

- `system_event_log` — append-only platform-level audit of significant
  state changes. Written only by application services and Edge
  Functions; never by clients.
- `audit_log` — generic catch-all audit log.
- `event_log` — generic immutable append-only event log.

## RLS

Every table in the list above has `ENABLE ROW LEVEL SECURITY` and a
default-deny posture. Policies in `009_rls_policies.sql` allow:

- `platform_admin` — bypass org filter; full read.
- `org_owner` — full CRUD within their organisation.
- `org_operator` — read/write within their organisation.
- `system_event_log`, `audit_log`, `event_log` — read scoped to org;
  no client writes (service_role only).

## Indexes

Every `organisation_id`, `facility_id`, `product_id`, and other FK has
a btree index. Composite indexes on common query patterns (e.g.
`(organisation_id, status) where deleted_at is null`) are present on
the high-traffic tables.
