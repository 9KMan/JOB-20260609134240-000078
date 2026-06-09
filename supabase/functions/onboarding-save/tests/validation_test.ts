// Unit tests for validation.ts.
// Run with: deno test -A supabase/functions/onboarding-save/tests/validation_test.ts
//
// These tests assert that the validator rejects malformed payloads and
// accepts well-formed ones, returning a clean OnboardingPayload on success.

import { assertEquals, assertThrows } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { validatePayload, ValidationError } from "../validation.ts";

function makeBasePayload(): Record<string, unknown> {
  return {
    organisation: {
      slug: "acme-co",
      name: "Acme Co",
      country_code: "US",
    },
    facilities: [
      { temp_id: "f1", code: "HQ", name: "Headquarters", country_code: "US" },
    ],
    products: [
      { temp_id: "p1", sku: "P-1", name: "Widget", unit: "ea" },
    ],
    ingredients: [
      { temp_id: "i1", sku: "I-1", name: "Sugar", default_unit: "kg" },
    ],
    recipes: [
      {
        temp_id: "r1",
        product_temp_id: "p1",
        version: 1,
        name: "Widget recipe",
        yield_quantity: 100,
        yield_unit: "ea",
      },
    ],
    recipe_ingredients: [
      { recipe_temp_id: "r1", ingredient_temp_id: "i1", quantity: 5, unit: "kg" },
    ],
    cost_pools: [
      { temp_id: "cp1", code: "MAT", name: "Material", category: "material" },
    ],
    labour_standards: [
      { temp_id: "ls1", facility_temp_id: "f1", role: "operator", rate_per_hour: 20 },
    ],
    pricing_configurations: [
      { temp_id: "pc1", product_temp_id: "p1", channel: "wholesale", base_price: 10 },
    ],
    retail_commitments: [
      { temp_id: "rc1", product_temp_id: "p1", customer_name: "Acme Buyer", committed_price: 12.5 },
    ],
  };
}

Deno.test("accepts a well-formed payload", () => {
  const out = validatePayload(makeBasePayload());
  assertEquals(out.organisation.slug, "acme-co");
  assertEquals(out.products.length, 1);
  assertEquals(out.recipe_ingredients.length, 1);
});

Deno.test("rejects a payload that is not an object", () => {
  assertThrows(
    () => validatePayload("not an object"),
    ValidationError,
  );
});

Deno.test("rejects a payload missing organisation", () => {
  const p = makeBasePayload() as Record<string, unknown>;
  delete p.organisation;
  assertThrows(() => validatePayload(p), ValidationError);
});

Deno.test("rejects invalid country_code", () => {
  const p = makeBasePayload();
  (p.organisation as Record<string, unknown>).country_code = "usa";
  try {
    validatePayload(p);
    throw new Error("expected throw");
  } catch (e) {
    if (!(e instanceof ValidationError)) throw e;
    const codes = e.issues.map((i) => i.path);
    if (!codes.some((c) => c.includes("country_code"))) {
      throw new Error("expected country_code issue");
    }
  }
});

Deno.test("rejects duplicate temp_id in same section", () => {
  const p = makeBasePayload();
  p.products = [
    { temp_id: "p1", sku: "P-1", name: "A" },
    { temp_id: "p1", sku: "P-2", name: "B" },
  ];
  try {
    validatePayload(p);
    throw new Error("expected throw");
  } catch (e) {
    if (!(e instanceof ValidationError)) throw e;
    if (!e.issues.some((i) => i.path.includes("temp_id"))) {
      throw new Error("expected duplicate temp_id issue");
    }
  }
});

Deno.test("rejects recipe referencing unknown product", () => {
  const p = makeBasePayload();
  (p.recipes as Array<Record<string, unknown>>)[0].product_temp_id = "missing";
  try {
    validatePayload(p);
    throw new Error("expected throw");
  } catch (e) {
    if (!(e instanceof ValidationError)) throw e;
    if (!e.issues.some((i) => i.path.includes("product_temp_id"))) {
      throw new Error("expected product_temp_id cross-ref issue");
    }
  }
});

Deno.test("rejects cost_pool with invalid category", () => {
  const p = makeBasePayload();
  (p.cost_pools as Array<Record<string, unknown>>)[0].category = "magic";
  try {
    validatePayload(p);
    throw new Error("expected throw");
  } catch (e) {
    if (!(e instanceof ValidationError)) throw e;
    if (!e.issues.some((i) => i.path.includes("category"))) {
      throw new Error("expected category issue");
    }
  }
});

Deno.test("rejects negative quantity", () => {
  const p = makeBasePayload();
  (p.recipe_ingredients as Array<Record<string, unknown>>)[0].quantity = -1;
  try {
    validatePayload(p);
    throw new Error("expected throw");
  } catch (e) {
    if (!(e instanceof ValidationError)) throw e;
    if (!e.issues.some((i) => i.path.includes("quantity"))) {
      throw new Error("expected quantity issue");
    }
  }
});
