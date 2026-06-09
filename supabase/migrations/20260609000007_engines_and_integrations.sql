-- 007_engines_and_integrations.sql
-- Assessment engine, verification engine, and external shipment integrations.

-- =============================================================================
-- assessment_engine: scoring bands and assessment criteria.
-- =============================================================================
do $$ begin
  create type assessment_band as enum ('A', 'B', 'C', 'D', 'F');
exception when duplicate_object then null; end $$;

create table if not exists public.assessment_engine (
  id              uuid primary key default uuid_generate_v4(),
  organisation_id uuid not null references public.organisations(id) on delete cascade,
  name            text not null check (char_length(name) between 1 and 200),
  description     text,
  band            assessment_band not null,
  score_min       numeric(6, 2) not null check (score_min >= 0 and score_min <= 100),
  score_max       numeric(6, 2) not null check (score_max >= 0 and score_max <= 100),
  criteria        jsonb not null default '[]'::jsonb,
  is_active       boolean not null default true,
  effective_from  timestamptz not null default now(),
  effective_to    timestamptz,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  deleted_at      timestamptz,
  check (score_max >= score_min),
  check (effective_to is null or effective_to > effective_from)
);

drop trigger if exists trg_assessment_engine_updated_at on public.assessment_engine;
create trigger trg_assessment_engine_updated_at
before update on public.assessment_engine
for each row execute function public.tg_set_updated_at();

create index if not exists idx_assessment_engine_org_band
  on public.assessment_engine (organisation_id, band) where deleted_at is null;

-- =============================================================================
-- verification_engine: verification status tracking.
-- =============================================================================
do $$ begin
  create type verification_status as enum (
    'unverified', 'pending', 'in_review', 'verified', 'rejected', 'expired'
  );
exception when duplicate_object then null; end $$;

create table if not exists public.verification_engine (
  id              uuid primary key default uuid_generate_v4(),
  organisation_id uuid not null references public.organisations(id) on delete cascade,
  subject_type    text not null check (subject_type in (
                    'organisation', 'facility', 'product', 'ingredient', 'supplier', 'batch'
                  )),
  subject_id      uuid not null,
  status          verification_status not null default 'unverified',
  evidence        jsonb not null default '{}'::jsonb,
  verified_by     uuid references auth.users(id) on delete set null,
  verified_at     timestamptz,
  expires_at      timestamptz,
  notes           text,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  deleted_at      timestamptz
);

drop trigger if exists trg_verification_engine_updated_at on public.verification_engine;
create trigger trg_verification_engine_updated_at
before update on public.verification_engine
for each row execute function public.tg_set_updated_at();

create index if not exists idx_verification_engine_org_subject
  on public.verification_engine (organisation_id, subject_type, subject_id) where deleted_at is null;
create index if not exists idx_verification_engine_org_status
  on public.verification_engine (organisation_id, status) where deleted_at is null;

-- =============================================================================
-- shipment_integrations: external system hooks.
-- =============================================================================
do $$ begin
  create type integration_direction as enum ('inbound', 'outbound', 'bidirectional');
exception when duplicate_object then null; end $$;

do $$ begin
  create type integration_status as enum ('active', 'paused', 'error', 'disabled');
exception when duplicate_object then null; end $$;

create table if not exists public.shipment_integrations (
  id              uuid primary key default uuid_generate_v4(),
  organisation_id uuid not null references public.organisations(id) on delete cascade,
  name            text not null check (char_length(name) between 1 and 200),
  provider        text not null,
  direction       integration_direction not null default 'inbound',
  status          integration_status not null default 'active',
  endpoint_url    text,
  secret_ref      text,
  config          jsonb not null default '{}'::jsonb,
  last_synced_at  timestamptz,
  last_error      text,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  deleted_at      timestamptz
);

drop trigger if exists trg_shipment_integrations_updated_at on public.shipment_integrations;
create trigger trg_shipment_integrations_updated_at
before update on public.shipment_integrations
for each row execute function public.tg_set_updated_at();

create index if not exists idx_shipment_integrations_org_status
  on public.shipment_integrations (organisation_id, status) where deleted_at is null;
