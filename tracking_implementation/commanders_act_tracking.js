// Commanders Act — P0 event tracking
// Events fire after server confirmation, never on UI action alone.

const tcVars = window.tc_vars || {};

function hasAnalyticsConsent() {
  return window.tC?.privacyCenter?.getConsent?.("analytics") === true;
}

function hasValue(value) {
  return value !== undefined && value !== null && value !== "";
}

function validateRequiredParams(eventName, params, requiredKeys) {
  const missing = requiredKeys.filter((key) => !hasValue(params[key]));

  if (missing.length > 0) {
    console.error(`[tracking] ${eventName} blocked. Missing parameters: ${missing.join(", ")}`);
    return false;
  }

  return true;
}

function pushTrackingEvent(eventName, params) {
  if (!hasAnalyticsConsent()) {
    console.warn(`[tracking] ${eventName} blocked. Analytics consent not granted.`);
    return null;
  }

  const payload = {
    event: eventName,
    environment: tcVars.env || "production",
    page_name: tcVars.page_name || "",
    ...params,
  };

  window.dataLayer = window.dataLayer || [];
  window.dataLayer.push(payload);

  if (window.tC?.event?.track) {
    window.tC.event.track(eventName, payload);
  }

  return payload;
}

// claim_submitted
// Trigger: after /api/v2/claims/submit returns HTTP 202.
// claim_id must come from the API response.

export function trackClaimSubmitted({
  userId,
  claimId,
  claimType,
  hasDocuments,
}) {
  const eventName = "claim_submitted";

  const params = {
    user_id: userId,
    claim_id: claimId,
    claim_type: claimType,
    has_documents: hasDocuments ? "true" : "false",
  };

  const isValid = validateRequiredParams(eventName, params, [
    "user_id",
    "claim_id",
    "claim_type",
  ]);

  if (!isValid) return null;

  return pushTrackingEvent(eventName, params);
}

// payment_completed
// Trigger: after payment confirmation.
// transaction_id must come from the payment provider or backend response.
// amount must be sent in major currency units, for example 49.99, not 4999.

export function trackPaymentCompleted({
  userId,
  transactionId,
  amount,
  currency,
  paymentMethod,
  claimId,
}) {
  const eventName = "payment_completed";

  const params = {
    user_id: userId,
    transaction_id: transactionId,
    amount,
    currency,
    payment_method: paymentMethod,
    claim_id: claimId || "",
  };

  const isValid = validateRequiredParams(eventName, params, [
    "user_id",
    "transaction_id",
    "amount",
    "currency",
    "payment_method",
  ]);

  if (!isValid) return null;

  if (typeof amount !== "number" || amount <= 0) {
    console.error("[tracking] payment_completed blocked. amount must be a positive number.");
    return null;
  }

  return pushTrackingEvent(eventName, params);
}
