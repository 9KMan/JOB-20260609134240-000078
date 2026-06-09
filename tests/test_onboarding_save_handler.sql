-- test_onboarding_save_handler.sql
-- Integration test for public.onboarding_save_atomic, the SQL function that
-- backs the onboarding-save Edge Function. Confirms a complete onboarding
-- payload writes the expected rows in a single transaction.
--
-- Run after migrations 001-011 are applied. Uses service_role to call the
-- function; production code never exposes the service key to clients.

begin;

-- Minimal valid payload. Slugs, SKUs and codes are unique to this test.
select * from public.onboarding_save_atomic(jsonb_build_object(
  'organisation', jsonb_build_object(
    'slug', 'test-onb-' || substr(md5(random()::text), 1, 8),
    'name', 'Test Onboarding Co',
    'country_code', 'US',
    'timezone', 'UTC'
  ),
  'facilities', jsonb_build_array(
    jsonb_build_object(
      'temp_id', 'fac-1',
      'code', 'MAIN',
      'name', 'Main Plant',
      'country_code', 'US'
    )
  ),
  'products', jsonb_build_array(
    jsonb_build_object('temp_id', 'p-1', 'sku', 'P-1', 'name', 'Product 1', 'unit', 'kg'),
    jsonb_build_object('temp_id', 'p-2', 'sku', 'P-2', 'name', 'Product 2', 'unit', 'ea')
  ),
  'ingredients', jsonb_build_array(
    jsonb_build_object('temp_id', 'i-1', 'sku', 'I-1', 'name', 'Ingredient 1', 'default_unit', 'kg',
                       'allergens', jsonb_build_array('gluten'))
  ),
  'recipes', jsonb_build_array(
    jsonb_build_object('temp_id', 'r-1', 'product_temp_id', 'p-1', 'version', 1,
                       'name', 'Recipe v1', 'yield_quantity', 100, 'yield_unit', 'kg')
  ),
  'recipe_ingredients', jsonb_build_array(
    jsonb_build_object('recipe_temp_id', 'r-1', 'ingredient_temp_id', 'i-1',
                       'quantity', 50, 'unit', 'kg')
  ),
  'cost_pools', jsonb_build_array(
    jsonb_build_object('temp_id', 'cp-1', 'code', 'MAT', 'name', 'Material', 'category', 'material'),
    jsonb_build_object('temp_id', 'cp-2', 'code', 'LAB', 'name', 'Labour',  'category', 'labour')
  ),
  'labour_standards', jsonb_build_array(
    jsonb_build_object('temp_id', 'ls-1', 'facility_temp_id', 'fac-1',
                       'role', 'operator', 'rate_per_hour', 25, 'currency_code', 'USD')
  ),
  'pricing_configurations', jsonb_build_array(
    jsonb_build_object('temp_id', 'pc-1', 'product_temp_id', 'p-1',
                       'channel', 'wholesale', 'base_price', 12.5, 'margin_pct', 20,
                       'rounding_rule', 'cent')
  ),
  'retail_commitments', jsonb_build_array(
    jsonb_build_object('temp_id', 'rc-1', 'product_temp_id', 'p-1',
                       'customer_name', 'Acme Co', 'committed_price', 14.99, 'currency_code', 'USD')
  )
)) as sections;

-- After the call, verify row counts in the last org.
do $$
declare
  v_org_id    uuid;
  v_products  int;
  v_ing       int;
  v_recipes   int;
  v_ri        int;
  v_pools     int;
  v_labour    int;
  v_pricing   int;
  v_retail    int;
begin
  select id into v_org_id from public.organisations
  where slug like 'test-onb-%' order by created_at desc limit 1;

  select count(*) into v_products   from public.products       where organisation_id = v_org_id;
  select count(*) into v_ing        from public.ingredients    where organisation_id = v_org_id;
  select count(*) into v_recipes    from public.recipes        where organisation_id = v_org_id;
  select count(*) into v_ri         from public.recipe_ingredients ri
                                   join public.recipes r on r.id = ri.recipe_id
                                   where r.organisation_id = v_org_id;
  select count(*) into v_pools      from public.cost_pools     where organisation_id = v_org_id;
  select count(*) into v_labour     from public.labour_standards where organisation_id = v_org_id;
  select count(*) into v_pricing    from public.pricing_configurations pc
                                   join public.products p on p.id = pc.product_id
                                   where p.organisation_id = v_org_id;
  select count(*) into v_retail     from public.retail_commitments rc
                                   join public.products p on p.id = rc.product_id
                                   where p.organisation_id = v_org_id;

  if v_products <> 2 then raise exception 'expected 2 products, got %', v_products; end if;
  if v_ing      <> 1 then raise exception 'expected 1 ingredient, got %', v_ing; end if;
  if v_recipes  <> 1 then raise exception 'expected 1 recipe, got %', v_recipes; end if;
  if v_ri       <> 1 then raise exception 'expected 1 recipe_ingredient, got %', v_ri; end if;
  if v_pools    <> 2 then raise exception 'expected 2 cost_pools, got %', v_pools; end if;
  if v_labour   <> 1 then raise exception 'expected 1 labour_standard, got %', v_labour; end if;
  if v_pricing  <> 1 then raise exception 'expected 1 pricing_configuration, got %', v_pricing; end if;
  if v_retail   <> 1 then raise exception 'expected 1 retail_commitment, got %', v_retail; end if;
  raise notice 'PASS: onboarding_save_atomic wrote expected rows';
end $$;

-- Cleanup.
do $$
declare v_org_id uuid;
begin
  select id into v_org_id from public.organisations where slug like 'test-onb-%' limit 1;
  if v_org_id is not null then
    delete from public.organisations where id = v_org_id; -- cascades everywhere.
  end if;
end $$;

rollback;
