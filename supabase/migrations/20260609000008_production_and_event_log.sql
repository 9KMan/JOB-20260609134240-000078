-- 008_production_and_event_log.sql
-- Production batches, batch cost records, and the platform-wide system event log.

-- =============================================================================
-- production_batches: batch records (facility, product, quantity, yield, status).
-- =============================================================================
create table if not exists public.production_batches (
  id                  uuid primary key default uuid_generate_v4(),
  organisation_id     uuid not null references public.organisations(id) on delete cascade,
  facility_id         uuid not null references public.facilities(id) on delete restrict,
  product_id          uuid not null references public.products(id) on delete restrict,
  recipe_id           uuid references public.recipes(id) on delete set null,
  batch_code          text not null,
  planned_quantity    numeric(14, 4) not null check (planned_quantity > 0),
  actual_quantity     numeric(14, 4) check (actual_quantity is null or actual_quantity >= 0),
  yield_pct           numeric(7, 4) check (yield_pct is null or (yield_pct >= 0 and yield_pct <= 1000)),
  status              batch_status not null default 'planned',
  started_at          timestamptz,
  completed_at        timestamptz,
  operator_user_id    uuid references auth.users(id) on delete set null,
  notes               text,
  metadata            jsonb not null default '{}'::jsonb,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  deleted_at          timestamptz,
  unique (organisation_id, batch_code)
);

drop trigger if exists trg_production_batches_updated_at on public.production_batches;
create trigger trg_production_batches_updated_at
before update on public.production_batches
for each row execute function public.tg_set_updated_at();

create index if not exists idx_production_batches_org_facility_status
  on public.production_batches (organisation_id, facility_id, status) where deleted_at is null;
create index if not exists idx_production_batches_org_product
  on public.production_batches (organisation_id, product_id) where deleted_at is null;
create index if not exists idx_production_batches_org_started
  on public.production_batches (organisation_id, started_at desc) where deleted_at is null;

-- =============================================================================
-- batch_cost_records: cost breakdown per batch (links cost pools).
-- =============================================================================
create table if not exists public.batch_cost_records (
  id              uuid primary key default uuid_generate_v4(),
  organisation_id uuid not null references public.organisations(id) on delete cascade,
  batch_id        uuid not null references public.production_batches(id) on delete cascade,
  cost_pool_id    uuid not null references public.cost_pools(id) on delete restrict,
  amount          numeric(14, 4) not null check (amount >= 0),
  currency_code   char(3) not null default 'USD'
                  check (currency_code ~ '^[A-Z]{3}$'),
  notes           text,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  deleted_at      timestamptz,
  unique (batch_id, cost_pool_id)
);

drop trigger if exists trg_batch_cost_records_updated_at on public.batch_cost_records;
create trigger trg_batch_cost_records_updated_at
before update on public.batch_cost_records
for each row execute function public.tg_set_updated_at();

create index if not exists idx_batch_cost_records_org_batch
  on public.batch_cost_records (organisation_id, batch_id) where deleted_at is null;

-- =============================================================================
-- system_event_log: platform-level audit of significant state changes.
-- Written ONLY by application services and Edge Functions; never by clients.
-- =============================================================================
do $$ begin
  create type system_event_type as enum (
    'assessment_band_changed',
    'verification_status_changed',
    'recipe_version_activated',
    'maturity_level_changed',
    'onboarding_completed',
    'seasonal_profile_recalibrated'
  );
exception when duplicate_object then null; end $$;

create table if not exists public.system_event_log (
  id              bigserial primary key,
  organisation_id uuid references public.organisations(id) on delete cascade,
  event_type      system_event_type not null,
  actor_user_id   uuid references auth.users(id) on delete set null,
  entity_type     text not null,
  entity_id       text not null,
  payload         jsonb not null default '{}'::jsonb,
  occurred_at     timestamptz not null default now()
);

create index if not exists idx_system_event_log_org_type_time
  on public.system_event_log (organisation_id, event_type, occurred_at desc);
create index if not exists idx_system_event_log_entity
  on public.system_event_log (entity_type, entity_id, occurred_at desc);

-- =============================================================================
-- user_roles: platform-wide role per user (cross-cutting, distinct from
-- per-organisation membership role). Required by the spec.
-- =============================================================================
do $$ begin
  create type platform_role as enum (
    'platform_admin', 'org_owner', 'org_operator'
  );
exception when duplicate_object then null; end $$;

create table if not exists public.user_roles (
  id              uuid primary key default uuid_generate_v4(),
  user_id         uuid not null references auth.users(id) on delete cascade,
  organisation_id uuid references public.organisations(id) on delete cascade,
  role            platform_role not null,
  granted_by      uuid references auth.users(id) on delete set null,
  granted_at      timestamptz not null default now(),
  unique (user_id, organisation_id, role)
);

create index if not exists idx_user_roles_user
  on public.user_roles (user_id);
create index if not exists idx_user_roles_org_role
  on public.user_roles (organisation_id, role);
