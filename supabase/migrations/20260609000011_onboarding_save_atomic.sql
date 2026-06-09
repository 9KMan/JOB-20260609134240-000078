-- 011_onboarding_save_atomic.sql
-- PostgreSQL function that performs the full onboarding save in a single
-- transaction. Invoked by the onboarding-save Edge Function via service role.
-- Any error raises and the entire transaction is rolled back.

create or replace function public.onboarding_save_atomic(
  p_payload jsonb
)
returns table (
  section text,
  ids     uuid[]
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_org_id          uuid;
  v_facility_ids    uuid[] := '{}';
  v_product_ids     uuid[] := '{}';
  v_ingredient_ids  uuid[] := '{}';
  v_recipe_ids      uuid[] := '{}';
  v_cost_pool_ids   uuid[] := '{}';
  v_labour_ids      uuid[] := '{}';
  v_pricing_ids     uuid[] := '{}';
  v_retail_ids      uuid[] := '{}';
  v_new_id          uuid;
  v_temp_to_id      jsonb := '{}'::jsonb;
  v_org             jsonb;
  v_facility        jsonb;
  v_product         jsonb;
  v_ingredient      jsonb;
  v_recipe          jsonb;
  v_rxi             jsonb;
  v_cp              jsonb;
  v_ls              jsonb;
  v_pc              jsonb;
  v_rc              jsonb;
begin
  v_org := p_payload->'organisation';

  -- 1. organisation
  insert into public.organisations (id, slug, name, legal_name, country_code, timezone, settings, onboarded_at)
  values (
    coalesce((v_org->>'id')::uuid, uuid_generate_v4()),
    v_org->>'slug',
    v_org->>'name',
    v_org->>'legal_name',
    v_org->>'country_code',
    coalesce(v_org->>'timezone', 'UTC'),
    coalesce(v_org->'settings', '{}'::jsonb),
    now()
  )
  on conflict (slug) do update set
    name = excluded.name,
    updated_at = now()
  returning id into v_org_id;

  -- 2. facilities
  v_facility_ids := '{}';
  if p_payload ? 'facilities' then
    for v_facility in select * from jsonb_array_elements(p_payload->'facilities')
    loop
      insert into public.facilities (organisation_id, code, name, site, address_line1, address_line2,
                                     city, region, country_code, timezone, is_active)
      values (
        v_org_id,
        v_facility->>'code',
        v_facility->>'name',
        v_facility->>'site',
        v_facility->>'address_line1',
        v_facility->>'address_line2',
        v_facility->>'city',
        v_facility->>'region',
        v_facility->>'country_code',
        coalesce(v_facility->>'timezone', 'UTC'),
        coalesce((v_facility->>'is_active')::boolean, true)
      )
      on conflict (organisation_id, code) do update set name = excluded.name
      returning id into v_new_id;
      v_facility_ids := array_append(v_facility_ids, v_new_id);
      v_temp_to_id := v_temp_to_id || jsonb_build_object(
        'facility:' || (v_facility->>'temp_id'),
        v_new_id::text
      );
    end loop;
  end if;

  -- 3. products
  v_product_ids := '{}';
  if p_payload ? 'products' then
    for v_product in select * from jsonb_array_elements(p_payload->'products')
    loop
      insert into public.products (organisation_id, sku, name, description, unit, is_active)
      values (
        v_org_id,
        v_product->>'sku',
        v_product->>'name',
        v_product->>'description',
        coalesce(v_product->>'unit', 'ea'),
        coalesce((v_product->>'is_active')::boolean, true)
      )
      on conflict (organisation_id, sku) do update set name = excluded.name
      returning id into v_new_id;
      v_product_ids := array_append(v_product_ids, v_new_id);
      v_temp_to_id := v_temp_to_id || jsonb_build_object(
        'product:' || (v_product->>'temp_id'),
        v_new_id::text
      );
    end loop;
  end if;

  -- 4. ingredients
  v_ingredient_ids := '{}';
  if p_payload ? 'ingredients' then
    for v_ingredient in select * from jsonb_array_elements(p_payload->'ingredients')
    loop
      insert into public.ingredients (organisation_id, sku, name, category, default_unit, allergens, is_active)
      values (
        v_org_id,
        v_ingredient->>'sku',
        v_ingredient->>'name',
        v_ingredient->>'category',
        coalesce(v_ingredient->>'default_unit', 'kg'),
        coalesce(
          (select array_agg(value) from jsonb_array_elements_text(coalesce(v_ingredient->'allergens', '[]'::jsonb))),
          '{}'
        ),
        coalesce((v_ingredient->>'is_active')::boolean, true)
      )
      on conflict (organisation_id, sku) do update set name = excluded.name
      returning id into v_new_id;
      v_ingredient_ids := array_append(v_ingredient_ids, v_new_id);
      v_temp_to_id := v_temp_to_id || jsonb_build_object(
        'ingredient:' || (v_ingredient->>'temp_id'),
        v_new_id::text
      );
    end loop;
  end if;

  -- 5. recipes (versioned per product)
  v_recipe_ids := '{}';
  if p_payload ? 'recipes' then
    for v_recipe in select * from jsonb_array_elements(p_payload->'recipes')
    loop
      insert into public.recipes (organisation_id, product_id, version, name, yield_quantity, yield_unit, notes, is_current, published_at)
      values (
        v_org_id,
        (v_temp_to_id->>('product:' || (v_recipe->>'product_temp_id')))::uuid,
        (v_recipe->>'version')::int,
        v_recipe->>'name',
        (v_recipe->>'yield_quantity')::numeric,
        coalesce(v_recipe->>'yield_unit', 'ea'),
        v_recipe->>'notes',
        coalesce((v_recipe->>'is_current')::boolean, true),
        now()
      )
      on conflict (organisation_id, product_id, version) do update set name = excluded.name
      returning id into v_new_id;
      v_recipe_ids := array_append(v_recipe_ids, v_new_id);
      v_temp_to_id := v_temp_to_id || jsonb_build_object(
        'recipe:' || (v_recipe->>'temp_id'),
        v_new_id::text
      );
    end loop;
  end if;

  -- 6. recipe_ingredients
  if p_payload ? 'recipe_ingredients' then
    for v_rxi in select * from jsonb_array_elements(p_payload->'recipe_ingredients')
    loop
      insert into public.recipe_ingredients (recipe_id, ingredient_id, quantity, unit, sequence, notes)
      values (
        (v_temp_to_id->>('recipe:' || (v_rxi->>'recipe_temp_id')))::uuid,
        (v_temp_to_id->>('ingredient:' || (v_rxi->>'ingredient_temp_id')))::uuid,
        (v_rxi->>'quantity')::numeric,
        v_rxi->>'unit',
        coalesce((v_rxi->>'sequence')::int, 0),
        v_rxi->>'notes'
      );
    end loop;
  end if;

  -- 7. cost_pools
  v_cost_pool_ids := '{}';
  if p_payload ? 'cost_pools' then
    for v_cp in select * from jsonb_array_elements(p_payload->'cost_pools')
    loop
      insert into public.cost_pools (organisation_id, code, name, category, description, is_active)
      values (
        v_org_id,
        v_cp->>'code',
        v_cp->>'name',
        v_cp->>'category',
        v_cp->>'description',
        coalesce((v_cp->>'is_active')::boolean, true)
      )
      on conflict (organisation_id, code) do update set name = excluded.name
      returning id into v_new_id;
      v_cost_pool_ids := array_append(v_cost_pool_ids, v_new_id);
    end loop;
  end if;

  -- 8. labour_standards
  v_labour_ids := '{}';
  if p_payload ? 'labour_standards' then
    for v_ls in select * from jsonb_array_elements(p_payload->'labour_standards')
    loop
      insert into public.labour_standards (organisation_id, facility_id, role, rate_per_hour, currency_code,
                                          effective_from, effective_to)
      values (
        v_org_id,
        case
          when v_ls->>'facility_temp_id' is null then null
          else (v_temp_to_id->>('facility:' || (v_ls->>'facility_temp_id')))::uuid
        end,
        v_ls->>'role',
        (v_ls->>'rate_per_hour')::numeric,
        coalesce(v_ls->>'currency_code', 'USD'),
        coalesce((v_ls->>'effective_from')::timestamptz, now()),
        (v_ls->>'effective_to')::timestamptz
      )
      returning id into v_new_id;
      v_labour_ids := array_append(v_labour_ids, v_new_id);
    end loop;
  end if;

  -- 9. pricing_configurations
  v_pricing_ids := '{}';
  if p_payload ? 'pricing_configurations' then
    for v_pc in select * from jsonb_array_elements(p_payload->'pricing_configurations')
    loop
      insert into public.pricing_configurations (organisation_id, product_id, channel, currency_code,
                                                 base_price, margin_pct, rounding_rule, effective_from, effective_to)
      values (
        v_org_id,
        (v_temp_to_id->>('product:' || (v_pc->>'product_temp_id')))::uuid,
        v_pc->>'channel',
        coalesce(v_pc->>'currency_code', 'USD'),
        (v_pc->>'base_price')::numeric,
        (v_pc->>'margin_pct')::numeric,
        coalesce(v_pc->>'rounding_rule', 'none'),
        coalesce((v_pc->>'effective_from')::timestamptz, now()),
        (v_pc->>'effective_to')::timestamptz
      )
      on conflict (organisation_id, product_id, channel, effective_from) do update
        set base_price = excluded.base_price
      returning id into v_new_id;
      v_pricing_ids := array_append(v_pricing_ids, v_new_id);
    end loop;
  end if;

  -- 10. retail_commitments
  v_retail_ids := '{}';
  if p_payload ? 'retail_commitments' then
    for v_rc in select * from jsonb_array_elements(p_payload->'retail_commitments')
    loop
      insert into public.retail_commitments (organisation_id, product_id, customer_name, committed_price,
                                            currency_code, effective_from, effective_to, contract_ref)
      values (
        v_org_id,
        (v_temp_to_id->>('product:' || (v_rc->>'product_temp_id')))::uuid,
        v_rc->>'customer_name',
        (v_rc->>'committed_price')::numeric,
        coalesce(v_rc->>'currency_code', 'USD'),
        coalesce((v_rc->>'effective_from')::timestamptz, now()),
        (v_rc->>'effective_to')::timestamptz,
        v_rc->>'contract_ref'
      )
      returning id into v_new_id;
      v_retail_ids := array_append(v_retail_ids, v_new_id);
    end loop;
  end if;

  -- Return one row per section with its array of ids.
  section := 'organisation';           ids := array[v_org_id];   return next;
  section := 'facilities';             ids := v_facility_ids;   return next;
  section := 'products';               ids := v_product_ids;    return next;
  section := 'ingredients';            ids := v_ingredient_ids; return next;
  section := 'recipes';                ids := v_recipe_ids;     return next;
  section := 'cost_pools';             ids := v_cost_pool_ids;  return next;
  section := 'labour_standards';       ids := v_labour_ids;     return next;
  section := 'pricing_configurations'; ids := v_pricing_ids;    return next;
  section := 'retail_commitments';     ids := v_retail_ids;     return next;
end;
$$;

-- Only the service_role (used by the Edge Function) may call this.
revoke all on function public.onboarding_save_atomic(jsonb) from public;
grant execute on function public.onboarding_save_atomic(jsonb) to service_role;
