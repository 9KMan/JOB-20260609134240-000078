// Deno edge function: onboarding-save-handler
//
// Receives a JSON payload describing a full supplier onboarding (org +
// facility + products + ingredients + recipes + cost pools + labour
// standards + pricing configuration + retail commitments).
//
// The handler validates every cross-reference, opens a single PostgreSQL
// transaction, and rolls back fully on any failure.
//
// Deployed with:  supabase functions deploy onboarding-save

import { createClient, SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";
import { validatePayload, ValidationError } from "./validation.ts";
import type { OnboardingPayload } from "./types.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL");
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY) {
  throw new Error(
    "Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY in function environment",
  );
}

const SERVICE_CLIENT: SupabaseClient = createClient(
  SUPABASE_URL,
  SUPABASE_SERVICE_ROLE_KEY,
  {
    auth: { persistSession: false, autoRefreshToken: false },
  },
);

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", ...CORS_HEADERS },
  });
}

async function saveOnboarding(
  payload: OnboardingPayload,
): Promise<{ ids: Record<string, string[]>; counts: Record<string, number> }> {
  // Single transaction: anything failing rolls everything back.
  const { data, error } = await SERVICE_CLIENT.rpc("onboarding_save_atomic", {
    p_payload: payload,
  });

  if (error) {
    throw new Error(`Atomic save failed: ${error.message}`);
  }
  return data as { ids: Record<string, string[]>; counts: Record<string, number> };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: CORS_HEADERS });
  }
  if (req.method !== "POST") {
    return jsonResponse({ error: "method_not_allowed" }, 405);
  }

  let body: unknown;
  try {
    body = await req.json();
  } catch (_e) {
    return jsonResponse({ error: "invalid_json", message: "Request body is not valid JSON" }, 400);
  }

  // 1. Validate the JSON contract.
  let payload: OnboardingPayload;
  try {
    payload = validatePayload(body);
  } catch (e) {
    if (e instanceof ValidationError) {
      return jsonResponse(
        { error: "validation_failed", issues: e.issues },
        422,
      );
    }
    return jsonResponse(
      { error: "validation_error", message: (e as Error).message },
      400,
    );
  }

  // 2. Execute the atomic save. Any database error propagates and the
  //    transaction inside the SQL function is rolled back.
  try {
    const result = await saveOnboarding(payload);

    // 3. Emit system_event_log entry: onboarding_completed.
    const orgId = payload.organisation.id;
    const { error: eventErr } = await SERVICE_CLIENT
      .from("system_event_log")
      .insert({
        organisation_id: orgId,
        event_type: "onboarding_completed",
        entity_type: "organisation",
        entity_id: orgId,
        payload: { counts: result.counts },
      });
    if (eventErr) {
      // Don't fail the response — onboarding already committed. Log only.
      console.error("system_event_log insert failed:", eventErr.message);
    }

    return jsonResponse({ ok: true, ...result }, 201);
  } catch (e) {
    return jsonResponse(
      { error: "save_failed", message: (e as Error).message },
      500,
    );
  }
});
