// TypeScript types for the onboarding JSON contract.
// The wizard must emit a payload that matches this shape; the validator
// enforces field-level rules.

export interface OrganisationInput {
  id?: string; // optional; if omitted, a uuid is generated
  slug: string;
  name: string;
  legal_name?: string | null;
  country_code: string;
  timezone?: string;
  settings?: Record<string, unknown>;
}

export interface FacilityInput {
  temp_id: string; // client-side reference for cross-linking
  organisation_id?: string; // ignored, set from parent org
  code: string;
  name: string;
  site?: string | null;
  address_line1?: string | null;
  address_line2?: string | null;
  city?: string | null;
  region?: string | null;
  country_code?: string | null;
  timezone?: string;
  is_active?: boolean;
}

export interface ProductInput {
  temp_id: string;
  sku: string;
  name: string;
  description?: string | null;
  unit?: string;
  is_active?: boolean;
}

export interface IngredientInput {
  temp_id: string;
  sku: string;
  name: string;
  category?: string | null;
  default_unit?: string;
  allergens?: string[];
  is_active?: boolean;
}

export interface RecipeInput {
  temp_id: string;
  product_temp_id: string;
  version: number;
  name: string;
  yield_quantity: number;
  yield_unit?: string;
  notes?: string | null;
  is_current?: boolean;
}

export interface RecipeIngredientInput {
  recipe_temp_id: string;
  ingredient_temp_id: string;
  quantity: number;
  unit: string;
  sequence?: number;
  notes?: string | null;
}

export interface CostPoolInput {
  temp_id: string;
  code: string;
  name: string;
  category: "material" | "labour" | "overhead" | "yield";
  description?: string | null;
  is_active?: boolean;
}

export interface LabourStandardInput {
  temp_id: string;
  facility_temp_id?: string | null;
  role: string;
  rate_per_hour: number;
  currency_code?: string;
  effective_from?: string;
  effective_to?: string | null;
}

export interface PricingConfigurationInput {
  temp_id: string;
  product_temp_id: string;
  channel: string;
  currency_code?: string;
  base_price: number;
  margin_pct?: number | null;
  rounding_rule?: "none" | "cent" | "nickel" | "dime" | "dollar";
  effective_from?: string;
  effective_to?: string | null;
}

export interface RetailCommitmentInput {
  temp_id: string;
  product_temp_id: string;
  customer_name: string;
  committed_price: number;
  currency_code?: string;
  effective_from?: string;
  effective_to?: string | null;
  contract_ref?: string | null;
}

export interface OnboardingPayload {
  organisation: OrganisationInput;
  facilities: FacilityInput[];
  products: ProductInput[];
  ingredients: IngredientInput[];
  recipes: RecipeInput[];
  recipe_ingredients: RecipeIngredientInput[];
  cost_pools: CostPoolInput[];
  labour_standards: LabourStandardInput[];
  pricing_configurations: PricingConfigurationInput[];
  retail_commitments: RetailCommitmentInput[];
}
