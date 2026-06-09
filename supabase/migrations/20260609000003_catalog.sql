-- 003_catalog.sql
-- Catalog: products, ingredients, recipes, and recipe ingredients.

-- products
create table if not exists public.products (
  id              uuid primary key default uuid_generate_v4(),
  organisation_id uuid not null references public.organisations(id) on delete cascade,
  sku             text not null,
  name            text not null check (char_length(name) between 1 and 200),
  description     text,
  unit            text not null default 'ea'
                  check (unit in ('ea', 'kg', 'g', 'lb', 'oz', 'l', 'ml', 'm', 'cm', 'pack', 'case')),
  is_active       boolean not null default true,
  metadata        jsonb not null default '{}'::jsonb,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  unique (organisation_id, sku)
);

drop trigger if exists trg_products_updated_at on public.products;
create trigger trg_products_updated_at
before update on public.products
for each row execute function public.tg_set_updated_at();

-- ingredients
create table if not exists public.ingredients (
  id              uuid primary key default uuid_generate_v4(),
  organisation_id uuid not null references public.organisations(id) on delete cascade,
  sku             text not null,
  name            text not null check (char_length(name) between 1 and 200),
  category        text,
  default_unit    text not null default 'kg'
                  check (default_unit in ('kg', 'g', 'lb', 'oz', 'l', 'ml', 'ea')),
  allergens       text[] not null default '{}',
  metadata        jsonb not null default '{}'::jsonb,
  is_active       boolean not null default true,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  unique (organisation_id, sku)
);

drop trigger if exists trg_ingredients_updated_at on public.ingredients;
create trigger trg_ingredients_updated_at
before update on public.ingredients
for each row execute function public.tg_set_updated_at();

-- recipes: versioned product formulations
create table if not exists public.recipes (
  id              uuid primary key default uuid_generate_v4(),
  organisation_id uuid not null references public.organisations(id) on delete cascade,
  product_id      uuid not null references public.products(id) on delete cascade,
  version         int  not null default 1 check (version > 0),
  name            text not null,
  yield_quantity  numeric(14, 4) not null default 1 check (yield_quantity > 0),
  yield_unit      text not null default 'ea'
                  check (yield_unit in ('ea', 'kg', 'g', 'lb', 'oz', 'l', 'ml', 'pack', 'case')),
  notes           text,
  is_current      boolean not null default true,
  published_at    timestamptz,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  unique (organisation_id, product_id, version)
);

drop trigger if exists trg_recipes_updated_at on public.recipes;
create trigger trg_recipes_updated_at
before update on public.recipes
for each row execute function public.tg_set_updated_at();

-- recipe ingredients: lines on a recipe
create table if not exists public.recipe_ingredients (
  id              uuid primary key default uuid_generate_v4(),
  recipe_id       uuid not null references public.recipes(id) on delete cascade,
  ingredient_id   uuid not null references public.ingredients(id) on delete restrict,
  quantity        numeric(14, 4) not null check (quantity > 0),
  unit            text not null
                  check (unit in ('kg', 'g', 'lb', 'oz', 'l', 'ml', 'ea')),
  sequence        int  not null default 0,
  notes           text,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  unique (recipe_id, ingredient_id)
);

drop trigger if exists trg_recipe_ingredients_updated_at on public.recipe_ingredients;
create trigger trg_recipe_ingredients_updated_at
before update on public.recipe_ingredients
for each row execute function public.tg_set_updated_at();
