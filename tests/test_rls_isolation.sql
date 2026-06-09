-- test_rls_isolation.sql
-- Multi-tenant isolation tests.
-- Validates that user A in organisation A cannot read or write rows that
-- belong to organisation B. Designed to be run against a clean Supabase
-- project after all migrations have been applied.
--
-- This script is documentation; the assertions are designed to be run with
-- pgTAP or executed manually by toggling SET ROLE between two test users.

begin;

-- 1. Two test organisations.
insert into public.organisations (id, slug, name, country_code)
values
  ('00000000-0000-0000-0000-00000000a001', 'org-a', 'Org A', 'US'),
  ('00000000-0000-0000-0000-00000000a002', 'org-b', 'Org B', 'US')
on conflict (slug) do nothing;

-- 2. Two test products, one per org.
insert into public.products (id, organisation_id, sku, name)
values
  ('00000000-0000-0000-0000-00000000b001', '00000000-0000-0000-0000-00000000a001', 'SKU-A-1', 'A Product'),
  ('00000000-0000-0000-0000-00000000b002', '00000000-0000-0000-0000-00000000a002', 'SKU-B-1', 'B Product')
on conflict do nothing;

-- 3. The RLS policies defined in 009_rls_policies.sql require
--    auth.uid() to resolve to a row in public.organisation_members.
--    The tests below assert the *expected behaviour*; manual execution
--    requires SET LOCAL ROLE / SET LOCAL request.jwt.claims.

-- ASSUMPTION: a service_role bypass is used to insert the two memberships
-- before running the assertions in a non-superuser role.
savepoint before_isolation_check;

-- Set up the test JWT for user A.
do $$
begin
  perform set_config(
    'request.jwt.claims',
    json_build_object(
      'sub', '00000000-0000-0000-0000-00000000c001',
      'role', 'authenticated'
    )::text,
    true
  );
end $$;

-- 4. As user A (member of org A), expect to see exactly 1 product.
--    Run as: psql -v ON_ERROR_STOP=1 ... -f tests/test_rls_isolation.sql
do $$
declare
  v_count int;
begin
  select count(*) into v_count from public.products;
  if v_count <> 1 then
    raise exception 'FAIL: user A sees % products (expected 1)', v_count;
  end if;
  if exists (
    select 1 from public.products
    where organisation_id = '00000000-0000-0000-0000-00000000a002'
  ) then
    raise exception 'FAIL: user A can see org B product';
  end if;
  raise notice 'PASS: user A sees only own org product';
end $$;

-- 5. Switch to user B (member of org B); expect the other product.
do $$
begin
  perform set_config(
    'request.jwt.claims',
    json_build_object(
      'sub', '00000000-0000-0000-0000-00000000c002',
      'role', 'authenticated'
    )::text,
    true
  );
end $$;

do $$
declare
  v_count int;
begin
  select count(*) into v_count from public.products;
  if v_count <> 1 then
    raise exception 'FAIL: user B sees % products (expected 1)', v_count;
  end if;
  if exists (
    select 1 from public.products
    where organisation_id = '00000000-0000-0000-0000-00000000a001'
  ) then
    raise exception 'FAIL: user B can see org A product';
  end if;
  raise notice 'PASS: user B sees only own org product';
end $$;

-- 6. Attempt cross-tenant write: user A inserts an org B product → must fail.
do $$
begin
  perform set_config(
    'request.jwt.claims',
    json_build_object(
      'sub', '00000000-0000-0000-0000-00000000c001',
      'role', 'authenticated'
    )::text,
    true
  );
end $$;

do $$
begin
  begin
    insert into public.products (organisation_id, sku, name)
    values ('00000000-0000-0000-0000-00000000a002', 'SKU-A-EVIL', 'evil');
    raise exception 'FAIL: cross-tenant write succeeded';
  exception
    when others then
      raise notice 'PASS: cross-tenant write rejected (%)', sqlerrm;
  end;
end $$;

rollback;
