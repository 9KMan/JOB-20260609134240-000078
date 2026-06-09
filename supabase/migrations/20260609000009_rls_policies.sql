-- 009_rls_policies.sql
-- Row-Level Security policies for all tenant-scoped tables.
-- Default deny: every table has RLS enabled, and a policy gates access.
-- Helpers resolve the caller's organisation memberships and platform role.

-- =============================================================================
-- Enable RLS on every table (idempotent).
-- =============================================================================
alter table public.organisations              enable row level security;
alter table public.profiles                   enable row level security;
alter table public.organisation_members       enable row level security;
alter table public.organisation_invites       enable row level security;
alter table public.audit_log                  enable row level security;
alter table public.event_log                  enable row level security;
alter table public.facilities                 enable row level security;
alter table public.raw_material_suppliers     enable row level security;
alter table public.ingredients                enable row level security;
alter table public.ingredient_lots            enable row level security;
alter table public.ingredient_price_history   enable row level security;
alter table public.products                   enable row level security;
alter table public.recipes                    enable row level security;
alter table public.recipe_ingredients         enable row level security;
alter table public.cost_pools                 enable row level security;
alter table public.labour_standards           enable row level security;
alter table public.pricing_configurations     enable row level security;
alter table public.pricing_configuration_history enable row level security;
alter table public.retail_commitments         enable row level security;
alter table public.production_batches         enable row level security;
alter table public.batch_cost_records         enable row level security;
alter table public.quality_events             enable row level security;
alter table public.corrective_actions         enable row level security;
alter table public.mock_recalls               enable row level security;
alter table public.assessment_engine          enable row level security;
alter table public.verification_engine        enable row level security;
alter table public.shipment_integrations      enable row level security;
alter table public.system_event_log           enable row level security;
alter table public.user_roles                 enable row level security;

-- =============================================================================
-- Helper functions (security-definer, stable) used by every policy.
-- =============================================================================

-- Returns the organisation ids the current user is a member of.
create or replace function public.current_user_org_ids()
returns setof uuid
language sql
stable
security definer
set search_path = public
as $$
  select organisation_id
  from public.organisation_members
  where user_id = auth.uid()
    and accepted_at is not null;
$$;

-- Returns true if the current user holds a platform_admin platform role.
create or replace function public.is_platform_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.user_roles
    where user_id = auth.uid()
      and role = 'platform_admin'
  );
$$;

-- Returns true if the current user has a platform role within the given org.
create or replace function public.has_org_role(p_org_id uuid, p_role platform_role)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.user_roles
    where user_id = auth.uid()
      and organisation_id = p_org_id
      and role = p_role
  );
$$;

-- Generic helper: is the current user a member of the given org?
create or replace function public.is_org_member(p_org_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.organisation_members
    where user_id = auth.uid()
      and organisation_id = p_org_id
      and accepted_at is not null
  );
$$;

-- =============================================================================
-- organisations
-- Members of an org can read it. platform_admin sees all. Owners can update.
-- =============================================================================
drop policy if exists organisations_select on public.organisations;
create policy organisations_select on public.organisations
  for select using (
    public.is_platform_admin() or public.is_org_member(id)
  );

drop policy if exists organisations_insert on public.organisations;
create policy organisations_insert on public.organisations
  for insert with check (public.is_platform_admin());

drop policy if exists organisations_update on public.organisations;
create policy organisations_update on public.organisations
  for update using (
    public.is_platform_admin() or public.has_org_role(id, 'org_owner')
  ) with check (
    public.is_platform_admin() or public.has_org_role(id, 'org_owner')
  );

drop policy if exists organisations_delete on public.organisations;
create policy organisations_delete on public.organisations
  for delete using (public.is_platform_admin());

-- =============================================================================
-- profiles
-- A user can read/update their own profile. platform_admin can read all.
-- =============================================================================
drop policy if exists profiles_select on public.profiles;
create policy profiles_select on public.profiles
  for select using (
    user_id = auth.uid() or public.is_platform_admin()
  );

drop policy if exists profiles_insert on public.profiles;
create policy profiles_insert on public.profiles
  for insert with check (user_id = auth.uid() or public.is_platform_admin());

drop policy if exists profiles_update on public.profiles;
create policy profiles_update on public.profiles
  for update using (user_id = auth.uid() or public.is_platform_admin())
  with check (user_id = auth.uid() or public.is_platform_admin());

drop policy if exists profiles_delete on public.profiles;
create policy profiles_delete on public.profiles
  for delete using (public.is_platform_admin());

-- =============================================================================
-- organisation_members
-- Members can read the membership list of orgs they belong to.
-- platform_admin sees all. org_owner can insert/update/delete.
-- =============================================================================
drop policy if exists organisation_members_select on public.organisation_members;
create policy organisation_members_select on public.organisation_members
  for select using (
    user_id = auth.uid() or public.is_platform_admin() or public.is_org_member(organisation_id)
  );

drop policy if exists organisation_members_insert on public.organisation_members;
create policy organisation_members_insert on public.organisation_members
  for insert with check (
    public.is_platform_admin() or public.has_org_role(organisation_id, 'org_owner')
  );

drop policy if exists organisation_members_update on public.organisation_members;
create policy organisation_members_update on public.organisation_members
  for update using (
    public.is_platform_admin() or public.has_org_role(organisation_id, 'org_owner')
  ) with check (
    public.is_platform_admin() or public.has_org_role(organisation_id, 'org_owner')
  );

drop policy if exists organisation_members_delete on public.organisation_members;
create policy organisation_members_delete on public.organisation_members
  for delete using (
    public.is_platform_admin() or public.has_org_role(organisation_id, 'org_owner')
  );

-- =============================================================================
-- organisation_invites
-- =============================================================================
drop policy if exists organisation_invites_select on public.organisation_invites;
create policy organisation_invites_select on public.organisation_invites
  for select using (
    public.is_platform_admin() or public.has_org_role(organisation_id, 'org_owner')
  );

drop policy if exists organisation_invites_insert on public.organisation_invites;
create policy organisation_invites_insert on public.organisation_invites
  for insert with check (
    public.is_platform_admin() or public.has_org_role(organisation_id, 'org_owner')
  );

drop policy if exists organisation_invites_update on public.organisation_invites;
create policy organisation_invites_update on public.organisation_invites
  for update using (
    public.is_platform_admin() or public.has_org_role(organisation_id, 'org_owner')
  ) with check (
    public.is_platform_admin() or public.has_org_role(organisation_id, 'org_owner')
  );

drop policy if exists organisation_invites_delete on public.organisation_invites;
create policy organisation_invites_delete on public.organisation_invites
  for delete using (
    public.is_platform_admin() or public.has_org_role(organisation_id, 'org_owner')
  );

-- =============================================================================
-- audit_log / event_log: org-scoped, read for members, write blocked for clients
-- (server-side inserts only). platform_admin sees all.
-- =============================================================================
drop policy if exists audit_log_select on public.audit_log;
create policy audit_log_select on public.audit_log
  for select using (
    organisation_id is null
      or public.is_platform_admin()
      or public.is_org_member(organisation_id)
  );

drop policy if exists audit_log_write on public.audit_log;
-- No insert/update/delete policies for non-superuser roles: writes must go
-- through service-role code (Edge Function). This is the default deny.
create policy audit_log_deny on public.audit_log
  for all using (public.is_platform_admin()) with check (public.is_platform_admin());

drop policy if exists event_log_select on public.event_log;
create policy event_log_select on public.event_log
  for select using (
    organisation_id is null
      or public.is_platform_admin()
      or public.is_org_member(organisation_id)
  );

drop policy if exists event_log_deny on public.event_log;
create policy event_log_deny on public.event_log
  for all using (public.is_platform_admin()) with check (public.is_platform_admin());

-- =============================================================================
-- Generic tenant-scoped tables.
-- organisation_id column gates everything; platform_admin bypasses org filter.
-- =============================================================================
do $$
declare
  t text;
  tables text[] := array[
    'facilities', 'raw_material_suppliers', 'ingredients', 'ingredient_lots',
    'ingredient_price_history', 'products', 'recipes',
    'cost_pools', 'labour_standards', 'pricing_configurations',
    'pricing_configuration_history', 'retail_commitments', 'production_batches',
    'batch_cost_records', 'quality_events', 'corrective_actions', 'mock_recalls',
    'assessment_engine', 'verification_engine', 'shipment_integrations'
  ];
begin
  foreach t in array tables loop
    -- SELECT
    execute format('drop policy if exists %I_select on public.%I', t, t);
    execute format($f$
      create policy %I_select on public.%I
      for select using (
        public.is_platform_admin() or public.is_org_member(organisation_id)
      )
    $f$, t, t);

    -- INSERT
    execute format('drop policy if exists %I_insert on public.%I', t, t);
    execute format($f$
      create policy %I_insert on public.%I
      for insert with check (
        public.is_platform_admin()
        or (public.is_org_member(organisation_id)
            and (public.has_org_role(organisation_id, ''org_owner'')
                 or public.has_org_role(organisation_id, ''org_operator'')))
      )
    $f$, t, t);

    -- UPDATE
    execute format('drop policy if exists %I_update on public.%I', t, t);
    execute format($f$
      create policy %I_update on public.%I
      for update using (
        public.is_platform_admin() or public.is_org_member(organisation_id)
      ) with check (
        public.is_platform_admin() or public.is_org_member(organisation_id)
      )
    $f$, t, t);

    -- DELETE (soft-delete only at the application layer; RLS allows it)
    execute format('drop policy if exists %I_delete on public.%I', t, t);
    execute format($f$
      create policy %I_delete on public.%I
      for delete using (
        public.is_platform_admin()
        or public.has_org_role(organisation_id, ''org_owner'')
      )
    $f$, t, t);
  end loop;
end $$;

-- =============================================================================
-- recipe_ingredients: organisation_id is reached via the parent recipe.
-- Custom policies join to recipes to compute membership.
-- =============================================================================
drop policy if exists recipe_ingredients_select on public.recipe_ingredients;
create policy recipe_ingredients_select on public.recipe_ingredients
  for select using (
    public.is_platform_admin() or exists (
      select 1
      from public.recipes r
      where r.id = recipe_ingredients.recipe_id
        and public.is_org_member(r.organisation_id)
    )
  );

drop policy if exists recipe_ingredients_insert on public.recipe_ingredients;
create policy recipe_ingredients_insert on public.recipe_ingredients
  for insert with check (
    public.is_platform_admin() or exists (
      select 1
      from public.recipes r
      where r.id = recipe_ingredients.recipe_id
        and public.is_org_member(r.organisation_id)
        and (public.has_org_role(r.organisation_id, 'org_owner')
             or public.has_org_role(r.organisation_id, 'org_operator'))
    )
  );

drop policy if exists recipe_ingredients_update on public.recipe_ingredients;
create policy recipe_ingredients_update on public.recipe_ingredients
  for update using (
    public.is_platform_admin() or exists (
      select 1
      from public.recipes r
      where r.id = recipe_ingredients.recipe_id
        and public.is_org_member(r.organisation_id)
    )
  ) with check (
    public.is_platform_admin() or exists (
      select 1
      from public.recipes r
      where r.id = recipe_ingredients.recipe_id
        and public.is_org_member(r.organisation_id)
    )
  );

drop policy if exists recipe_ingredients_delete on public.recipe_ingredients;
create policy recipe_ingredients_delete on public.recipe_ingredients
  for delete using (
    public.is_platform_admin() or exists (
      select 1
      from public.recipes r
      where r.id = recipe_ingredients.recipe_id
        and public.is_org_member(r.organisation_id)
        and public.has_org_role(r.organisation_id, 'org_owner')
    )
  );

-- =============================================================================
-- system_event_log: clients never write directly. Reads scoped to org.
-- =============================================================================
drop policy if exists system_event_log_select on public.system_event_log;
create policy system_event_log_select on public.system_event_log
  for select using (
    organisation_id is null
      or public.is_platform_admin()
      or public.is_org_member(organisation_id)
  );

drop policy if exists system_event_log_deny on public.system_event_log;
create policy system_event_log_deny on public.system_event_log
  for all using (public.is_platform_admin()) with check (public.is_platform_admin());

-- =============================================================================
-- user_roles
-- =============================================================================
drop policy if exists user_roles_select on public.user_roles;
create policy user_roles_select on public.user_roles
  for select using (
    user_id = auth.uid() or public.is_platform_admin()
      or (organisation_id is not null and public.is_org_member(organisation_id))
  );

drop policy if exists user_roles_write on public.user_roles;
create policy user_roles_write on public.user_roles
  for all using (public.is_platform_admin())
  with check (public.is_platform_admin());

-- =============================================================================
-- service_role bypass: Supabase's service_role bypasses RLS by design. The
-- policies above apply to anon and authenticated roles. service_role is used
-- by the Edge Function save handler and by migrations.
-- =============================================================================
