-- 005_costing_and_pricing.sql
-- Costing, pricing, and per-batch cost records.

-- =============================================================================
-- cost_pools: cost categories (material, labour, overhead, yield).
-- =============================================================================
do $$ begin
  create type cost_pool_category as enum ('material', 'labour', 'overhead', 'yield');
exception when duplicate_object then null; end $$;

create table if not exists public.cost_pools (
  id              uuid primary key default uuid_generate_v4(),
  organisation_id uuid not null references public.organisations(id) on delete cascade,
  code            text not null,
  name            text not null check (char_length(name) between 1 and 200),
  category        cost_pool_category not null,
  description     text,
  is_active       boolean not null default true,
  metadata        jsonb not null default '{}'::jsonb,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  deleted_at      timestamptz,
  unique (organisation_id, code)
);

drop trigger if exists trg_cost_pools_updated_at on public.cost_pools;
create trigger trg_cost_pools_updated_at
before update on public.cost_pools
for each row execute function public.tg_set_updated_at();

create index if not exists idx_cost_pools_org_category
  on public.cost_pools (organisation_id, category) where deleted_at is null;

-- =============================================================================
-- labour_standards: rate tables per facility / role.
-- =============================================================================
create table if not exists public.labour_standards (
  id              uuid primary key default uuid_generate_v4(),
  organisation_id uuid not null references public.organisations(id) on delete cascade,
  facility_id     uuid references public.facilities(id) on delete cascade,
  role            text not null,
  rate_per_hour   numeric(14, 4) not null check (rate_per_hour >= 0),
  currency_code   char(3) not null default 'USD'
                  check (currency_code ~ '^[A-Z]{3}$'),
  effective_from  timestamptz not null default now(),
  effective_to    timestamptz,
  notes           text,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  deleted_at      timestamptz,
  check (effective_to is null or effective_to > effective_from)
);

drop trigger if exists trg_labour_standards_updated_at on public.labour_standards;
create trigger trg_labour_standards_updated_at
before update on public.labour_standards
for each row execute function public.tg_set_updated_at();

create index if not exists idx_labour_standards_org_facility
  on public.labour_standards (organisation_id, facility_id) where deleted_at is null;

-- =============================================================================
-- pricing_configurations: pricing rules per product/channel.
-- =============================================================================
create table if not exists public.pricing_configurations (
  id                 uuid primary key default uuid_generate_v4(),
  organisation_id    uuid not null references public.organisations(id) on delete cascade,
  product_id         uuid not null references public.products(id) on delete cascade,
  channel            text not null,
  currency_code      char(3) not null default 'USD'
                     check (currency_code ~ '^[A-Z]{3}$'),
  base_price         numeric(14, 4) not null check (base_price >= 0),
  margin_pct         numeric(7, 4) check (margin_pct is null or (margin_pct >= 0 and margin_pct <= 1000)),
  rounding_rule      text not null default 'none'
                     check (rounding_rule in ('none', 'cent', 'nickel', 'dime', 'dollar')),
  effective_from     timestamptz not null default now(),
  effective_to       timestamptz,
  is_active          boolean not null default true,
  metadata           jsonb not null default '{}'::jsonb,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  deleted_at         timestamptz,
  unique (organisation_id, product_id, channel, effective_from),
  check (effective_to is null or effective_to > effective_from)
);

drop trigger if exists trg_pricing_configurations_updated_at on public.pricing_configurations;
create trigger trg_pricing_configurations_updated_at
before update on public.pricing_configurations
for each row execute function public.tg_set_updated_at();

create index if not exists idx_pricing_configurations_org_product
  on public.pricing_configurations (organisation_id, product_id) where deleted_at is null;
create index if not exists idx_pricing_configurations_active
  on public.pricing_configurations (organisation_id, is_active) where deleted_at is null;

-- =============================================================================
-- pricing_configuration_history: audit trail of pricing changes.
-- =============================================================================
create table if not exists public.pricing_configuration_history (
  id                      uuid primary key default uuid_generate_v4(),
  pricing_configuration_id uuid not null references public.pricing_configurations(id) on delete cascade,
  organisation_id         uuid not null references public.organisations(id) on delete cascade,
  changed_by              uuid references auth.users(id) on delete set null,
  change_type             text not null check (change_type in ('created', 'updated', 'superseded', 'deactivated')),
  previous_state          jsonb,
  new_state               jsonb not null,
  changed_at              timestamptz not null default now()
);

create index if not exists idx_pricing_configuration_history_pc
  on public.pricing_configuration_history (pricing_configuration_id, changed_at desc);
create index if not exists idx_pricing_configuration_history_org
  on public.pricing_configuration_history (organisation_id, changed_at desc);

-- =============================================================================
-- retail_commitments: agreed retail prices per product / customer.
-- =============================================================================
create table if not exists public.retail_commitments (
  id              uuid primary key default uuid_generate_v4(),
  organisation_id uuid not null references public.organisations(id) on delete cascade,
  product_id      uuid not null references public.products(id) on delete cascade,
  customer_name   text not null,
  committed_price numeric(14, 4) not null check (committed_price >= 0),
  currency_code   char(3) not null default 'USD'
                  check (currency_code ~ '^[A-Z]{3}$'),
  effective_from  timestamptz not null default now(),
  effective_to    timestamptz,
  contract_ref    text,
  notes           text,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  deleted_at      timestamptz,
  check (effective_to is null or effective_to > effective_from)
);

drop trigger if exists trg_retail_commitments_updated_at on public.retail_commitments;
create trigger trg_retail_commitments_updated_at
before update on public.retail_commitments
for each row execute function public.tg_set_updated_at();

create index if not exists idx_retail_commitments_org_product
  on public.retail_commitments (organisation_id, product_id) where deleted_at is null;
