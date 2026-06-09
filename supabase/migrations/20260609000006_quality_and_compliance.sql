-- 006_quality_and_compliance.sql
-- Quality events, corrective actions, and mock recall drills.

-- =============================================================================
-- quality_events: QC checks and deviations.
-- =============================================================================
do $$ begin
  create type quality_event_type as enum (
    'inspection', 'deviation', 'complaint', 'spec_check', 'release', 'rejection'
  );
exception when duplicate_object then null; end $$;

do $$ begin
  create type quality_event_severity as enum ('info', 'minor', 'major', 'critical');
exception when duplicate_object then null; end $$;

do $$ begin
  create type quality_event_status as enum ('open', 'investigating', 'resolved', 'closed');
exception when duplicate_object then null; end $$;

create table if not exists public.quality_events (
  id              uuid primary key default uuid_generate_v4(),
  organisation_id uuid not null references public.organisations(id) on delete cascade,
  facility_id     uuid references public.facilities(id) on delete set null,
  product_id      uuid references public.products(id) on delete set null,
  ingredient_id   uuid references public.ingredients(id) on delete set null,
  ingredient_lot_id uuid references public.ingredient_lots(id) on delete set null,
  event_type      quality_event_type not null,
  severity        quality_event_severity not null default 'minor',
  status          quality_event_status not null default 'open',
  title           text not null check (char_length(title) between 1 and 200),
  description     text,
  detected_at     timestamptz not null default now(),
  resolved_at     timestamptz,
  reported_by     uuid references auth.users(id) on delete set null,
  metadata        jsonb not null default '{}'::jsonb,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  deleted_at      timestamptz
);

drop trigger if exists trg_quality_events_updated_at on public.quality_events;
create trigger trg_quality_events_updated_at
before update on public.quality_events
for each row execute function public.tg_set_updated_at();

create index if not exists idx_quality_events_org_status
  on public.quality_events (organisation_id, status) where deleted_at is null;
create index if not exists idx_quality_events_org_product
  on public.quality_events (organisation_id, product_id) where deleted_at is null;
create index if not exists idx_quality_events_org_detected
  on public.quality_events (organisation_id, detected_at desc) where deleted_at is null;

-- =============================================================================
-- corrective_actions: CAPA records linked to quality events.
-- =============================================================================
do $$ begin
  create type corrective_action_status as enum (
    'planned', 'in_progress', 'verification', 'closed', 'cancelled'
  );
exception when duplicate_object then null; end $$;

create table if not exists public.corrective_actions (
  id              uuid primary key default uuid_generate_v4(),
  organisation_id uuid not null references public.organisations(id) on delete cascade,
  quality_event_id uuid not null references public.quality_events(id) on delete cascade,
  title           text not null check (char_length(title) between 1 and 200),
  description     text,
  root_cause      text,
  status          corrective_action_status not null default 'planned',
  owner_user_id   uuid references auth.users(id) on delete set null,
  due_at          timestamptz,
  closed_at       timestamptz,
  effectiveness_verified boolean not null default false,
  metadata        jsonb not null default '{}'::jsonb,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  deleted_at      timestamptz
);

drop trigger if exists trg_corrective_actions_updated_at on public.corrective_actions;
create trigger trg_corrective_actions_updated_at
before update on public.corrective_actions
for each row execute function public.tg_set_updated_at();

create index if not exists idx_corrective_actions_org_event
  on public.corrective_actions (organisation_id, quality_event_id) where deleted_at is null;
create index if not exists idx_corrective_actions_org_status
  on public.corrective_actions (organisation_id, status) where deleted_at is null;

-- =============================================================================
-- mock_recalls: recall drill records.
-- =============================================================================
create table if not exists public.mock_recalls (
  id                 uuid primary key default uuid_generate_v4(),
  organisation_id    uuid not null references public.organisations(id) on delete cascade,
  product_id         uuid not null references public.products(id) on delete cascade,
  facility_id        uuid references public.facilities(id) on delete set null,
  scenario_name      text not null check (char_length(scenario_name) between 1 and 200),
  recall_status      recall_status not null default 'initiated',
  severity           recall_severity not null default 'medium',
  initiated_at       timestamptz not null default now(),
  closed_at          timestamptz,
  affected_lot_codes text[] not null default '{}',
  traceability_score numeric(5, 2) check (traceability_score is null or (traceability_score >= 0 and traceability_score <= 100)),
  notes              text,
  metadata           jsonb not null default '{}'::jsonb,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  deleted_at         timestamptz
);

drop trigger if exists trg_mock_recalls_updated_at on public.mock_recalls;
create trigger trg_mock_recalls_updated_at
before update on public.mock_recalls
for each row execute function public.tg_set_updated_at();

create index if not exists idx_mock_recalls_org_product
  on public.mock_recalls (organisation_id, product_id) where deleted_at is null;
create index if not exists idx_mock_recalls_org_status
  on public.mock_recalls (organisation_id, recall_status) where deleted_at is null;
