// Commanders Act — P0 event tracking
// Fired client-side after server confirmation. Never on UI action alone.
// tc_vars is the Commanders Act data layer object (injected by TMS).

const tc_vars = window.tc_vars || {};

// ── Shared ────────────────────────────────────────────────────────────────────

function getConsentState() {
  return window.tC?.privacyCenter?.getConsent?.("analytics") === true;
}

function validateParams(eventName, required, params) {
  const missing = required.filter(k => !params[k] || params[k] === "");
  if (missing.length > 0) {
    console.error(`[tracking] ${eventName} blocked — missing: ${missing.join(", ")}`);
    return false;
  }
  return true;
}

function push(payload) {
  if (!getConsentState()) {
    console.warn("[tracking] event blocked — analytics consent not granted");
    return null;
  }
  window.dataLayer = window.dataLayer || [];
  window.dataLayer.push(payload);
  tC.event.track(payload.event, payload);
  return payload;
}

// ── claim_submitted (P0) ──────────────────────────────────────────────────────
// Trigger: after /api/v2/claims/submit returns 202. Never on button tap.
// claim_id must come from the API response body — never generated client-side.

export function trackClaimSubmitted({ userId, claimId, claimType, hasDocuments }) {
  const required = ["userId", "claimId", "claimType"];
  if (!validateParams("claim_submitted", required, { userId, claimId, claimType })) return null;

  const payload = {
    event:         "claim_submitted",
    user_id:       userId,
    claim_id:      claimId,
    claim_type:    claimType,                          // "property" | "vehicle" | "health" | "travel"
    has_documents: hasDocuments ? "true" : "false",
    page_name:     tc_vars.page_name   || "",
    env:           tc_vars.env         || "production",
  };

  return push(payload);
}

// ── payment_completed (P0) ────────────────────────────────────────────────────
// Trigger: after Stripe webhook confirmed and transaction_id is available.
// amount in major currency units (EUR). Never cents.

export function trackPaymentCompleted({ userId, transactionId, amount, currency, paymentMethod, claimId }) {
  const required = ["userId", "transactionId", "amount", "currency", "paymentMethod"];
  if (!validateParams("payment_completed", required, { userId, transactionId, amount, currency, paymentMethod })) return null;

  if (typeof amount !== "number" || amount <= 0) {
    console.error("[tracking] payment_completed blocked — amount must be a positive number");
    return null;
  }

  const payload = {
    event:          "payment_completed",
    user_id:        userId,
    transaction_id: transactionId,
    amount:         amount,
    currency:       currency,                          // ISO 4217 — "EUR"
    payment_method: paymentMethod,                     // "card" | "sepa_debit" | "apple_pay" | "google_pay"
    claim_id:       claimId || "",                     // links payment to claim for Finance reconciliation
    env:            tc_vars.env || "production",
  };

  return push(payload);
}
