// Payload validation for the onboarding save handler.
// Pure functions; no database calls. The atomic SQL function re-validates
// cross-references inside the transaction.

import type {
  OnboardingPayload,
  ProductInput,
  IngredientInput,
  RecipeInput,
  RecipeIngredientInput,
  FacilityInput,
  CostPoolInput,
  LabourStandardInput,
  PricingConfigurationInput,
  RetailCommitmentInput,
} from "./types.ts";

export class ValidationError extends Error {
  constructor(public issues: { path: string; message: string }[]) {
    super(`Validation failed: ${issues.length} issue(s)`);
    this.name = "ValidationError";
  }
}

type Issues = { path: string; message: string }[];

const COUNTRY_RE = /^[A-Z]{2}$/;
const SLUG_RE = /^[a-z0-9][a-z0-9-]{1,62}[a-z0-9]$/;
const CURRENCY_RE = /^[A-Z]{3}$/;

const PRODUCT_UNITS = new Set([
  "ea", "kg", "g", "lb", "oz", "l", "ml", "m", "cm", "pack", "case",
]);
const INGREDIENT_UNITS = new Set(["kg", "g", "lb", "oz", "l", "ml", "ea"]);
const RECIPE_UNITS = new Set([
  "ea", "kg", "g", "lb", "oz", "l", "ml", "pack", "case",
]);
const RECIPE_INGREDIENT_UNITS = new Set(["kg", "g", "lb", "oz", "l", "ml", "ea"]);
const ROUNDING = new Set(["none", "cent", "nickel", "dime", "dollar"]);
const COST_POOL_CATS = new Set(["material", "labour", "overhead", "yield"]);

function isObject(v: unknown): v is Record<string, unknown> {
  return typeof v === "object" && v !== null && !Array.isArray(v);
}

function asArray(v: unknown, path: string, issues: Issues): unknown[] {
  if (!Array.isArray(v)) {
    issues.push({ path, message: "expected an array" });
    return [];
  }
  return v;
}

function requireString(
  v: unknown,
  path: string,
  issues: Issues,
  opts: { min?: number; max?: number; pattern?: RegExp } = {},
): string | undefined {
  if (typeof v !== "string") {
    issues.push({ path, message: "expected a string" });
    return undefined;
  }
  if (opts.min !== undefined && v.length < opts.min) {
    issues.push({ path, message: `length must be >= ${opts.min}` });
    return undefined;
  }
  if (opts.max !== undefined && v.length > opts.max) {
    issues.push({ path, message: `length must be <= ${opts.max}` });
    return undefined;
  }
  if (opts.pattern && !opts.pattern.test(v)) {
    issues.push({ path, message: `does not match pattern ${opts.pattern}` });
    return undefined;
  }
  return v;
}

function requireNumber(
  v: unknown,
  path: string,
  issues: Issues,
  opts: { min?: number; max?: number } = {},
): number | undefined {
  if (typeof v !== "number" || !Number.isFinite(v)) {
    issues.push({ path, message: "expected a finite number" });
    return undefined;
  }
  if (opts.min !== undefined && v < opts.min) {
    issues.push({ path, message: `must be >= ${opts.min}` });
    return undefined;
  }
  if (opts.max !== undefined && v > opts.max) {
    issues.push({ path, message: `must be <= ${opts.max}` });
    return undefined;
  }
  return v;
}

function requireEnum<T extends string>(
  v: unknown,
  path: string,
  issues: Issues,
  allowed: Set<T>,
): T | undefined {
  if (typeof v !== "string" || !allowed.has(v as T)) {
    issues.push({
      path,
      message: `must be one of: ${[...allowed].join(", ")}`,
    });
    return undefined;
  }
  return v as T;
}

function validateOrganisation(
  v: unknown,
  path: string,
  issues: Issues,
): { id: string | undefined; slug: string; name: string; country_code: string } | undefined {
  if (!isObject(v)) {
    issues.push({ path, message: "expected an object" });
    return undefined;
  }
  const slug = requireString(v.slug, `${path}.slug`, issues, { pattern: SLUG_RE });
  const name = requireString(v.name, `${path}.name`, issues, { min: 1, max: 200 });
  const country = requireString(v.country_code, `${path}.country_code`, issues, {
    pattern: COUNTRY_RE,
  });
  if (!slug || !name || !country) return undefined;
  return {
    id: typeof v.id === "string" ? v.id : undefined,
    slug,
    name,
    country_code: country,
  };
}

function validateFacility(v: unknown, path: string, issues: Issues): FacilityInput | undefined {
  if (!isObject(v)) {
    issues.push({ path, message: "expected an object" });
    return undefined;
  }
  const temp_id = requireString(v.temp_id, `${path}.temp_id`, issues);
  const code = requireString(v.code, `${path}.code`, issues, { min: 1, max: 64 });
  const name = requireString(v.name, `${path}.name`, issues, { min: 1, max: 200 });
  if (!temp_id || !code || !name) return undefined;
  const country = v.country_code;
  if (country !== undefined && country !== null && typeof country !== "string") {
    issues.push({ path: `${path}.country_code`, message: "must be string or null" });
  }
  if (typeof country === "string" && !COUNTRY_RE.test(country)) {
    issues.push({ path: `${path}.country_code`, message: "must match /^[A-Z]{2}$/" });
  }
  return v as FacilityInput;
}

function validateProduct(v: unknown, path: string, issues: Issues): ProductInput | undefined {
  if (!isObject(v)) {
    issues.push({ path, message: "expected an object" });
    return undefined;
  }
  const temp_id = requireString(v.temp_id, `${path}.temp_id`, issues);
  const sku = requireString(v.sku, `${path}.sku`, issues, { min: 1, max: 64 });
  const name = requireString(v.name, `${path}.name`, issues, { min: 1, max: 200 });
  if (!temp_id || !sku || !name) return undefined;
  if (v.unit !== undefined) requireEnum(v.unit, `${path}.unit`, issues, PRODUCT_UNITS);
  return v as ProductInput;
}

function validateIngredient(v: unknown, path: string, issues: Issues): IngredientInput | undefined {
  if (!isObject(v)) {
    issues.push({ path, message: "expected an object" });
    return undefined;
  }
  const temp_id = requireString(v.temp_id, `${path}.temp_id`, issues);
  const sku = requireString(v.sku, `${path}.sku`, issues, { min: 1, max: 64 });
  const name = requireString(v.name, `${path}.name`, issues, { min: 1, max: 200 });
  if (!temp_id || !sku || !name) return undefined;
  if (v.default_unit !== undefined) {
    requireEnum(v.default_unit, `${path}.default_unit`, issues, INGREDIENT_UNITS);
  }
  if (v.allergens !== undefined && !Array.isArray(v.allergens)) {
    issues.push({ path: `${path}.allergens`, message: "must be string[]" });
  }
  return v as IngredientInput;
}

function validateRecipe(
  v: unknown,
  path: string,
  issues: Issues,
): RecipeInput | undefined {
  if (!isObject(v)) {
    issues.push({ path, message: "expected an object" });
    return undefined;
  }
  const temp_id = requireString(v.temp_id, `${path}.temp_id`, issues);
  const product_temp_id = requireString(v.product_temp_id, `${path}.product_temp_id`, issues);
  const version = requireNumber(v.version, `${path}.version`, issues, { min: 1 });
  const name = requireString(v.name, `${path}.name`, issues, { min: 1, max: 200 });
  const yield_quantity = requireNumber(v.yield_quantity, `${path}.yield_quantity`, issues, { min: 0 });
  if (!temp_id || !product_temp_id || version === undefined || !name || yield_quantity === undefined) {
    return undefined;
  }
  if (v.yield_unit !== undefined) {
    requireEnum(v.yield_unit, `${path}.yield_unit`, issues, RECIPE_UNITS);
  }
  return v as RecipeInput;
}

function validateRecipeIngredient(
  v: unknown,
  path: string,
  issues: Issues,
): RecipeIngredientInput | undefined {
  if (!isObject(v)) {
    issues.push({ path, message: "expected an object" });
    return undefined;
  }
  const recipe_temp_id = requireString(v.recipe_temp_id, `${path}.recipe_temp_id`, issues);
  const ingredient_temp_id = requireString(
    v.ingredient_temp_id,
    `${path}.ingredient_temp_id`,
    issues,
  );
  const quantity = requireNumber(v.quantity, `${path}.quantity`, issues, { min: 0 });
  const unit = requireString(v.unit, `${path}.unit`, issues);
  if (!recipe_temp_id || !ingredient_temp_id || quantity === undefined || !unit) return undefined;
  if (!RECIPE_INGREDIENT_UNITS.has(unit)) {
    issues.push({ path: `${path}.unit`, message: "unsupported unit" });
  }
  return v as RecipeIngredientInput;
}

function validateCostPool(v: unknown, path: string, issues: Issues): CostPoolInput | undefined {
  if (!isObject(v)) {
    issues.push({ path, message: "expected an object" });
    return undefined;
  }
  const temp_id = requireString(v.temp_id, `${path}.temp_id`, issues);
  const code = requireString(v.code, `${path}.code`, issues, { min: 1, max: 64 });
  const name = requireString(v.name, `${path}.name`, issues, { min: 1, max: 200 });
  if (!temp_id || !code || !name) return undefined;
  if (v.category !== undefined) {
    requireEnum(v.category, `${path}.category`, issues, COST_POOL_CATS);
  }
  return v as CostPoolInput;
}

function validateLabourStandard(
  v: unknown,
  path: string,
  issues: Issues,
): LabourStandardInput | undefined {
  if (!isObject(v)) {
    issues.push({ path, message: "expected an object" });
    return undefined;
  }
  const temp_id = requireString(v.temp_id, `${path}.temp_id`, issues);
  const role = requireString(v.role, `${path}.role`, issues, { min: 1, max: 100 });
  const rate = requireNumber(v.rate_per_hour, `${path}.rate_per_hour`, issues, { min: 0 });
  if (!temp_id || !role || rate === undefined) return undefined;
  if (v.currency_code !== undefined) {
    if (typeof v.currency_code !== "string" || !CURRENCY_RE.test(v.currency_code)) {
      issues.push({ path: `${path}.currency_code`, message: "must be /^[A-Z]{3}$/" });
    }
  }
  return v as LabourStandardInput;
}

function validatePricing(
  v: unknown,
  path: string,
  issues: Issues,
): PricingConfigurationInput | undefined {
  if (!isObject(v)) {
    issues.push({ path, message: "expected an object" });
    return undefined;
  }
  const temp_id = requireString(v.temp_id, `${path}.temp_id`, issues);
  const product_temp_id = requireString(v.product_temp_id, `${path}.product_temp_id`, issues);
  const channel = requireString(v.channel, `${path}.channel`, issues, { min: 1, max: 64 });
  const base_price = requireNumber(v.base_price, `${path}.base_price`, issues, { min: 0 });
  if (!temp_id || !product_temp_id || !channel || base_price === undefined) return undefined;
  if (v.rounding_rule !== undefined) {
    requireEnum(v.rounding_rule, `${path}.rounding_rule`, issues, ROUNDING);
  }
  if (v.currency_code !== undefined) {
    if (typeof v.currency_code !== "string" || !CURRENCY_RE.test(v.currency_code)) {
      issues.push({ path: `${path}.currency_code`, message: "must be /^[A-Z]{3}$/" });
    }
  }
  if (v.margin_pct !== undefined && v.margin_pct !== null) {
    requireNumber(v.margin_pct, `${path}.margin_pct`, issues, { min: 0, max: 1000 });
  }
  return v as PricingConfigurationInput;
}

function validateRetail(
  v: unknown,
  path: string,
  issues: Issues,
): RetailCommitmentInput | undefined {
  if (!isObject(v)) {
    issues.push({ path, message: "expected an object" });
    return undefined;
  }
  const temp_id = requireString(v.temp_id, `${path}.temp_id`, issues);
  const product_temp_id = requireString(v.product_temp_id, `${path}.product_temp_id`, issues);
  const customer_name = requireString(v.customer_name, `${path}.customer_name`, issues, {
    min: 1,
    max: 200,
  });
  const committed_price = requireNumber(
    v.committed_price,
    `${path}.committed_price`,
    issues,
    { min: 0 },
  );
  if (!temp_id || !product_temp_id || !customer_name || committed_price === undefined) {
    return undefined;
  }
  if (v.currency_code !== undefined) {
    if (typeof v.currency_code !== "string" || !CURRENCY_RE.test(v.currency_code)) {
      issues.push({ path: `${path}.currency_code`, message: "must be /^[A-Z]{3}$/" });
    }
  }
  return v as RetailCommitmentInput;
}

function checkUniqueness<T extends { temp_id: string }>(
  arr: T[],
  label: string,
  issues: Issues,
): void {
  const seen = new Set<string>();
  for (let i = 0; i < arr.length; i++) {
    if (seen.has(arr[i].temp_id)) {
      issues.push({
        path: `${label}[${i}].temp_id`,
        message: `duplicate temp_id "${arr[i].temp_id}"`,
      });
    } else {
      seen.add(arr[i].temp_id);
    }
  }
}

export function validatePayload(input: unknown): OnboardingPayload {
  const issues: Issues = [];

  if (!isObject(input)) {
    throw new ValidationError([{ path: "$", message: "payload must be a JSON object" }]);
  }

  const org = validateOrganisation(input.organisation, "organisation", issues);
  const facilities = asArray(input.facilities, "facilities", issues)
    .map((f, i) => validateFacility(f, `facilities[${i}]`, issues))
    .filter((x): x is FacilityInput => x !== undefined);

  const products = asArray(input.products, "products", issues)
    .map((p, i) => validateProduct(p, `products[${i}]`, issues))
    .filter((x): x is ProductInput => x !== undefined);

  const ingredients = asArray(input.ingredients, "ingredients", issues)
    .map((p, i) => validateIngredient(p, `ingredients[${i}]`, issues))
    .filter((x): x is IngredientInput => x !== undefined);

  const recipes = asArray(input.recipes, "recipes", issues)
    .map((p, i) => validateRecipe(p, `recipes[${i}]`, issues))
    .filter((x): x is RecipeInput => x !== undefined);

  const recipe_ingredients = asArray(input.recipe_ingredients, "recipe_ingredients", issues)
    .map((p, i) => validateRecipeIngredient(p, `recipe_ingredients[${i}]`, issues))
    .filter((x): x is RecipeIngredientInput => x !== undefined);

  const cost_pools = asArray(input.cost_pools, "cost_pools", issues)
    .map((p, i) => validateCostPool(p, `cost_pools[${i}]`, issues))
    .filter((x): x is CostPoolInput => x !== undefined);

  const labour_standards = asArray(input.labour_standards, "labour_standards", issues)
    .map((p, i) => validateLabourStandard(p, `labour_standards[${i}]`, issues))
    .filter((x): x is LabourStandardInput => x !== undefined);

  const pricing_configurations = asArray(
    input.pricing_configurations,
    "pricing_configurations",
    issues,
  )
    .map((p, i) => validatePricing(p, `pricing_configurations[${i}]`, issues))
    .filter((x): x is PricingConfigurationInput => x !== undefined);

  const retail_commitments = asArray(input.retail_commitments, "retail_commitments", issues)
    .map((p, i) => validateRetail(p, `retail_commitments[${i}]`, issues))
    .filter((x): x is RetailCommitmentInput => x !== undefined);

  // Cross-reference checks (subset; the SQL function re-validates authoritatively).
  const productIds = new Set(products.map((p) => p.temp_id));
  const ingredientIds = new Set(ingredients.map((p) => p.temp_id));
  const recipeIds = new Set(recipes.map((p) => p.temp_id));
  const facilityIds = new Set(facilities.map((p) => p.temp_id));

  recipes.forEach((r, i) => {
    if (!productIds.has(r.product_temp_id)) {
      issues.push({
        path: `recipes[${i}].product_temp_id`,
        message: `references unknown product temp_id "${r.product_temp_id}"`,
      });
    }
  });

  recipe_ingredients.forEach((ri, i) => {
    if (!recipeIds.has(ri.recipe_temp_id)) {
      issues.push({
        path: `recipe_ingredients[${i}].recipe_temp_id`,
        message: `references unknown recipe temp_id "${ri.recipe_temp_id}"`,
      });
    }
    if (!ingredientIds.has(ri.ingredient_temp_id)) {
      issues.push({
        path: `recipe_ingredients[${i}].ingredient_temp_id`,
        message: `references unknown ingredient temp_id "${ri.ingredient_temp_id}"`,
      });
    }
  });

  pricing_configurations.forEach((pc, i) => {
    if (!productIds.has(pc.product_temp_id)) {
      issues.push({
        path: `pricing_configurations[${i}].product_temp_id`,
        message: `references unknown product temp_id "${pc.product_temp_id}"`,
      });
    }
  });

  retail_commitments.forEach((rc, i) => {
    if (!productIds.has(rc.product_temp_id)) {
      issues.push({
        path: `retail_commitments[${i}].product_temp_id`,
        message: `references unknown product temp_id "${rc.product_temp_id}"`,
      });
    }
  });

  labour_standards.forEach((ls, i) => {
    if (ls.facility_temp_id && !facilityIds.has(ls.facility_temp_id)) {
      issues.push({
        path: `labour_standards[${i}].facility_temp_id`,
        message: `references unknown facility temp_id "${ls.facility_temp_id}"`,
      });
    }
  });

  checkUniqueness(facilities, "facilities", issues);
  checkUniqueness(products, "products", issues);
  checkUniqueness(ingredients, "ingredients", issues);
  checkUniqueness(recipes, "recipes", issues);
  checkUniqueness(cost_pools, "cost_pools", issues);
  checkUniqueness(labour_standards, "labour_standards", issues);
  checkUniqueness(pricing_configurations, "pricing_configurations", issues);
  checkUniqueness(retail_commitments, "retail_commitments", issues);

  if (issues.length > 0) {
    throw new ValidationError(issues);
  }

  return {
    organisation: org as OnboardingPayload["organisation"],
    facilities,
    products,
    ingredients,
    recipes,
    recipe_ingredients,
    cost_pools,
    labour_standards,
    pricing_configurations,
    retail_commitments,
  };
}
