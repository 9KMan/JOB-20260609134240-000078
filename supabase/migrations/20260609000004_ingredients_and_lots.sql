-- 004_ingredients_and_lots.sql
-- Traceability layer: facilities, raw-material suppliers, ingredient lots, and price history.

-- =============================================================================
-- facilities: physical sites owned by an organisation.
-- =============================================================================
create table if not exists public.facilities (
  id              uuid primary key default uuid_generate_v4(),
  organisation_id uuid not null references public.organisations(id) on delete cascade,
  code            text not null,
  name            text not null check (char_length(name) between 1 and 200),
  site            text,
  address_line1   text,
  address_line2   text,
  city            text,
  region          text,
  country_code    char(2) check (country_code is null or country_code ~ '^[A-Z]{2}$'),
  timezone        text not null default 'UTC',
  is_active       boolean not null default true,
  metadata        jsonb not null default '{}'::jsonb,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  deleted_at      timestamptz,
  unique (organisation_id, code)
);

drop trigger if exists trg_facilities_updated_at on public.facilities;
create trigger trg_facilities_updated_at
before update on public.facilities
for each row execute function public.tg_set_updated_at();

create index if not exists idx_facilities_org_active
  on public.facilities (organisation_id) where deleted_at is null;

-- =============================================================================
-- raw_material_suppliers: supplier entity per org.
-- =============================================================================
create table if not exists public.raw_material_suppliers (
  id              uuid primary key default uuid_generate_v4(),
  organisation_id uuid not null references public.organisations(id) on delete cascade,
  code            text not null,
  name            text not null check (char_length(name) between 1 and 200),
  contact_name    text,
  contact_email   text,
  contact_phone   text,
  country_code    char(2) check (country_code is null or country_code ~ '^[A-Z]{2}$'),
  notes           text,
  is_active       boolean not null default true,
  metadata        jsonb not null default '{}'::jsonb,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  deleted_at      timestamptz,
  unique (organisation_id, code)
);

drop trigger if exists trg_raw_material_suppliers_updated_at on public.raw_material_suppliers;
create trigger trg_raw_material_suppliers_updated_at
before update on public.raw_material_suppliers
for each row execute function public.tg_set_updated_at();

create index if not exists idx_raw_material_suppliers_org
  on public.raw_material_suppliers (organisation_id) where deleted_at is null;

-- =============================================================================
-- ingredient_lots: lot tracking per ingredient.
-- =============================================================================
create table if not exists public.ingredient_lots (
  id                   uuid primary key default uuid_generate_v4(),
  organisation_id      uuid not null references public.organisations(id) on delete cascade,
  ingredient_id        uuid not null references public.ingredients(id) on delete restrict,
  supplier_id          uuid references public.raw_material_suppliers(id) on delete set null,
  facility_id          uuid references public.facilities(id) on delete set null,
  lot_code             text not null,
  received_at          timestamptz not null,
  expiry_at            timestamptz,
  quantity_received    numeric(14, 4) not null check (quantity_received >= 0),
  quantity_remaining   numeric(14, 4) not null check (quantity_remaining >= 0),
  unit                 text not null
                       check (unit in ('kg', 'g', 'lb', 'oz', 'l', 'ml', 'ea')),
  status               lot_status not null default 'received',
  cost_per_unit        numeric(14, 6) check (cost_per_unit is null or cost_per_unit >= 0),
  metadata             jsonb not null default '{}'::jsonb,
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now(),
  deleted_at           timestamptz,
  unique (organisation_id, lot_code)
);

drop trigger if exists trg_ingredient_lots_updated_at on public.ingredient_lots;
create trigger trg_ingredient_lots_updated_at
before update on public.ingredient_lots
for each row execute function public.tg_set_updated_at();

create index if not exists idx_ingredient_lots_org_ingredient
  on public.ingredient_lots (organisation_id, ingredient_id) where deleted_at is null;
create index if not exists idx_ingredient_lots_org_status
  on public.ingredient_lots (organisation_id, status) where deleted_at is null;
create index if not exists idx_ingredient_lots_facility
  on public.ingredient_lots (facility_id) where deleted_at is null;
create index if not exists idx_ingredient_lots_expiry
  on public.ingredient_lots (expiry_at) where deleted_at is null and expiry_at is not null;

-- =============================================================================
-- ingredient_price_history: time-series pricing per supplier/ingredient.
-- =============================================================================
create table if not exists public.ingredient_price_history (
  id              uuid primary key default uuid_generate_v4(),
  organisation_id uuid not null references public.organisations(id) on delete cascade,
  ingredient_id   uuid not null references public.ingredients(id) on delete cascade,
  supplier_id     uuid references public.raw_material_suppliers(id) on delete set null,
  unit            text not null
                  check (unit in ('kg', 'g', 'lb', 'oz', 'l', 'ml', 'ea')),
  price           numeric(14, 6) not null check (price >= 0),
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

drop trigger if exists trg_ingredient_price_history_updated_at on public.ingredient_price_history;
create trigger trg_ingredient_price_history_updated_at
before update on public.ingredient_price_history
for each row execute function public.tg_set_updated_at();

create index if not exists idx_ingredient_price_history_org_ingredient
  on public.ingredient_price_history (organisation_id, ingredient_id) where deleted_at is null;
create index if not exists idx_ingredient_price_history_effective
  on public.ingredient_price_history (ingredient_id, effective_from) where deleted_at is null;
