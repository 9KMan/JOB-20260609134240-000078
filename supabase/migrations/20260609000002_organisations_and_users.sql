-- 002_organisations_and_users.sql
-- Core tenancy tables: organisations, users (mirrored from auth.users), and membership roles.

-- organisations
-- Tenant root. Every business entity in the platform is rooted at an organisation.
create table if not exists public.organisations (
  id              uuid primary key default uuid_generate_v4(),
  slug            text not null unique
                  check (slug ~ '^[a-z0-9][a-z0-9-]{1,62}[a-z0-9]$'),
  name            text not null check (char_length(name) between 1 and 200),
  legal_name      text check (legal_name is null or char_length(legal_name) <= 250),
  country_code    char(2) not null check (country_code ~ '^[A-Z]{2}$'),
  timezone        text not null default 'UTC',
  settings        jsonb not null default '{}'::jsonb,
  onboarded_at    timestamptz,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  deleted_at      timestamptz
);

-- helper: keep updated_at fresh
create or replace function public.tg_set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists trg_organisations_updated_at on public.organisations;
create trigger trg_organisations_updated_at
before update on public.organisations
for each row execute function public.tg_set_updated_at();

-- profiles: 1-to-1 mirror of auth.users (the canonical identity table managed by Supabase Auth)
create table if not exists public.profiles (
  user_id         uuid primary key references auth.users(id) on delete cascade,
  full_name       text check (full_name is null or char_length(full_name) <= 200),
  email           text check (email is null or email ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$'),
  locale          text not null default 'en',
  avatar_url      text,
  metadata        jsonb not null default '{}'::jsonb,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);

drop trigger if exists trg_profiles_updated_at on public.profiles;
create trigger trg_profiles_updated_at
before update on public.profiles
for each row execute function public.tg_set_updated_at();

-- membership: a user can belong to multiple organisations with a role in each
create table if not exists public.organisation_members (
  id              uuid primary key default uuid_generate_v4(),
  organisation_id uuid not null references public.organisations(id) on delete cascade,
  user_id         uuid not null references auth.users(id) on delete cascade,
  role            user_role not null default 'viewer',
  invited_at      timestamptz not null default now(),
  accepted_at     timestamptz,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  unique (organisation_id, user_id)
);

drop trigger if exists trg_org_members_updated_at on public.organisation_members;
create trigger trg_org_members_updated_at
before update on public.organisation_members
for each row execute function public.tg_set_updated_at();

-- invites: pending membership invitations, valid until accepted
create table if not exists public.organisation_invites (
  id              uuid primary key default uuid_generate_v4(),
  organisation_id uuid not null references public.organisations(id) on delete cascade,
  email           text not null,
  role            user_role not null default 'viewer',
  token           text not null unique default encode(gen_random_bytes(24), 'hex'),
  invited_by      uuid references auth.users(id) on delete set null,
  expires_at      timestamptz not null default (now() + interval '14 days'),
  accepted_at     timestamptz,
  revoked_at      timestamptz,
  created_at      timestamptz not null default now()
);

-- generic catch-all audit log
create table if not exists public.audit_log (
  id              bigserial primary key,
  organisation_id uuid references public.organisations(id) on delete cascade,
  actor_user_id   uuid references auth.users(id) on delete set null,
  action          text not null,
  entity_type     text not null,
  entity_id       text,
  payload         jsonb not null default '{}'::jsonb,
  ip_address      inet,
  user_agent      text,
  created_at      timestamptz not null default now()
);

-- generic event log (immutable, append-only)
create table if not exists public.event_log (
  id              bigserial primary key,
  organisation_id uuid references public.organisations(id) on delete cascade,
  event_type      text not null,
  payload         jsonb not null default '{}'::jsonb,
  occurred_at     timestamptz not null default now()
);
