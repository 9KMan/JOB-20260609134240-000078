-- test_rollback.sql
-- Confirms that a single failed validation inside public.onboarding_save_atomic
-- rolls back the entire transaction. No rows should be visible to the test
-- caller after a forced failure.

begin;

-- Use a SAVEPOINT to wrap the test in a transaction that we can also discard.
savepoint sp_start;

select * from public.onboarding_save_atomic(jsonb_build_object(
  'organisation', jsonb_build_object(
    'slug', 'rollback-test-' || substr(md5(random()::text), 1, 8),
    'name', 'Rollback Co',
    'country_code', 'US'
  ),
  'facilities', jsonb_build_array(
    jsonb_build_object('temp_id', 'fac-1', 'code', 'HQ', 'name', 'HQ', 'country_code', 'US')
  ),
  'products', jsonb_build_array(
    jsonb_build_object('temp_id', 'p-1', 'sku', 'P-1', 'name', 'Product 1', 'unit', 'kg')
  ),
  'ingredients', jsonb_build_array(
    jsonb_build_object('temp_id', 'i-1', 'sku', 'I-1', 'name', 'Ingredient 1')
  ),
  'recipes', jsonb_build_array(
    -- Will fail later: bad product_temp_id reference.
    jsonb_build_object('temp_id', 'r-1', 'product_temp_id', 'does-not-exist',
                       'version', 1, 'name', 'Bad recipe', 'yield_quantity', 1)
  )
)) as sections;

-- If we got here, the function did not roll back. Force a failure.
do $$
begin
  raise exception 'FAIL: expected rollback to be triggered';
end $$;

rollback to savepoint sp_start;
rollback;
