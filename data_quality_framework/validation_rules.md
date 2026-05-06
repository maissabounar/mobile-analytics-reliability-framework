# Validation Rules

**Owner:** Data Analytics  
**Last updated:** 2025-10-15  
**Run schedule:** Daily at 08:30 CET  
**Output table:** `dq_alerts.daily_results`

This document defines the validation rules used to monitor mobile analytics reliability across iOS and Android.

The framework checks five areas:

- Completeness
- Uniqueness
- Conformity
- Timeliness
- Consistency
- Privacy and consent

The goal is to detect tracking issues before they affect dashboards, sales reporting, product decisions, or compliance reviews.

---

## Severity Levels

| Level | Meaning | Expected response |
|---|---|---|
| **P0** | Breaks a core metric, sales reporting, or consent compliance | Escalate within 4h, fix within 24h |
| **P1** | Degrades funnel analysis, campaign tracking, or product reporting | Fix within 1 week |
| **P2** | Low-risk data quality issue | Review during weekly analytics standup |

---

## C — Completeness

Completeness rules check that required fields are populated when they are expected.

| Rule | Event(s) | Threshold | Severity | BigQuery check |
|---|---|---|---|---|
| **C-01** `user_id` is not null | `payment_completed`, `claim_submitted`, `login_success`, `logout` | >0% warning, >1% critical | P0 | `check_null_user_id.sql` |
| **C-02** `transaction_id` is not null | `payment_completed`, `payment_refunded` | Any null value | P0 | `check_required_business_keys.sql` |
| **C-03** `claim_id` is not null | `claim_submitted`, `claim_approved`, `claim_rejected` | Any null value | P0 | `check_required_business_keys.sql` |
| **C-04** `amount` is not null and > 0 | `payment_completed` | Any null or zero value | P0 | `check_payment_amounts.sql` |
| **C-05** `step_index` is not null and between 1 and 6 | `onboarding_step_completed` | >2% warning, >5% critical | P1 | `check_onboarding_steps.sql` |
| **C-06** `auth_method` is not null | `login_success`, `signup_completed` | >1% null | P1 | `check_auth_method_quality.sql` |
| **C-07** `document_type` is not null | `document_uploaded` | >3% null | P2 | `check_document_metadata.sql` |

### Common failure patterns

| Issue | Typical cause |
|---|---|
| Missing `user_id` | User ID set after the event is fired |
| Missing `transaction_id` | Payment event fired before the payment callback resolves |
| Missing `claim_id` | Claim event fired before the backend returns the final ID |
| Missing `step_index` | Screen tracking implemented without the required step parameter |

> Implementation rule: business identifiers must come from confirmed backend responses, not from temporary client-side values.

---

## U — Uniqueness

Uniqueness rules check that conversion events are not duplicated for the same business key.

| Rule | Key | Event(s) | Threshold | Severity | BigQuery check |
|---|---|---|---|---|---|
| **U-01** No duplicate `transaction_id` | `transaction_id` | `payment_completed` | Any duplicate | P0 | `check_duplicate_conversions.sql` |
| **U-02** No duplicate `claim_id` | `claim_id` | `claim_submitted` | Any duplicate | P0 | `check_duplicate_conversions.sql` |
| **U-03** One onboarding step per user and step | `user_pseudo_id + step_index` | `onboarding_step_completed` | >1% duplicate steps | P1 | `check_duplicate_onboarding_steps.sql` |

### Duplicate gap classification

| Gap between duplicate events | Likely cause |
|---|---|
| < 1 second | Async callback race condition |
| 1–30 seconds | Double tap or missing UI debounce |
| > 30 seconds | Activity recreation, retry logic, or session replay issue |

Sales teams use conversion and transaction data to monitor revenue performance. Duplicate events inflate reported conversions when deduplication is not applied downstream.

---

## CF — Conformity

Conformity rules check that event names and parameter values follow the approved tracking taxonomy.

| Rule | Check | Threshold | Severity |
|---|---|---|---|
| **CF-01** Event name uses `snake_case` | No uppercase letters, spaces, or hyphens | Any non-compliant event | P1 |
| **CF-02** No deprecated events in production | Event name is not deprecated | Any traffic | P1 |
| **CF-03** `auth_method` uses approved values | `email`, `google`, `apple`, `sms` | Any invalid value | P1 |
| **CF-04** `error_type` uses approved values | Approved error taxonomy | >5% invalid values | P2 |
| **CF-05** `claim_type` uses approved values | `property`, `vehicle`, `health`, `travel` | Any invalid value | P1 |
| **CF-06** `platform` is valid | `IOS` or `ANDROID` | Any other value | P2 |

### Deprecated events

The following events should not appear in production data:

```text
submit_claim
notif_clicked
documentUploaded
payment_screen_view
user_registered
step_done
