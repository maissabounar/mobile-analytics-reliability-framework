# Validation Rules

**Owner:** Data Analytics  
**Updated:** 2025-10-15  
**Run schedule:** Daily at 08:30 CET via BigQuery Scheduled Queries → `dq_alerts.daily_results`

---

## Severity Definitions

| Level | Meaning | Response SLA |
|---|---|---|
| **P0** | Breaks financial reporting, GDPR compliance, or a core conversion metric | Fix within 24h, escalate within 4h |
| **P1** | Degrades a funnel or campaign workflow; incorrect but not financial-critical | Fix within 1 week |
| **P2** | Low-signal noise; informs but doesn't block decisions | Weekly review |

---

## C — Completeness

Missing required fields on events where they are unconditionally expected.

| Rule | Event(s) | Threshold | Severity | BigQuery check |
|---|---|---|---|---|
| **C-01** `user_id` non-null | `payment_completed`, `claim_submitted`, `login_success`, `logout` | >0% → WARNING · >1% → CRITICAL | P0 | `check_null_user_id.sql` |
| **C-02** `transaction_id` non-null | `payment_completed`, `payment_refunded` | Any null → CRITICAL | P0 | `check_null_user_id.sql` |
| **C-03** `claim_id` non-null | `claim_submitted`, `claim_approved`, `claim_rejected` | Any null → CRITICAL | P0 | `check_null_user_id.sql` |
| **C-04** `amount` non-null and > 0 | `payment_completed` | Any null or zero → CRITICAL | P0 | Ad hoc |
| **C-05** `step_index` non-null and in \[1–6\] | `onboarding_step_completed` | >2% null → WARNING · >5% → CRITICAL | P1 | `check_naming_compliance.sql` |
| **C-06** `auth_method` non-null | `login_success`, `signup_completed` | >1% null → WARNING | P1 | `check_naming_compliance.sql` |
| **C-07** `document_type` non-null | `document_uploaded` | >3% null → WARNING | P2 | Ad hoc |

**Audit-proven failure modes for C-01/C-02:**
- Android `setUserId()` called in a coroutine on `IO` dispatcher while `logEvent()` fires on `Main` — race condition
- `transaction_id` sourced from Stripe before async callback resolves — null 12.4% of the time pre-fix
- `claim_id` generated client-side before API returns — unreliable, now blocked by implementation rule

---

## U — Uniqueness

Conversion events that must have exactly one occurrence per business key.

| Rule | Key | Event(s) | Threshold | Severity | BigQuery check |
|---|---|---|---|---|---|
| **U-01** No duplicate `transaction_id` | `transaction_id` | `payment_completed` | Any duplicate → CRITICAL | P0 | `check_duplicate_conversions.sql` |
| **U-02** No duplicate `claim_id` | `claim_id` | `claim_submitted` | Any duplicate → CRITICAL | P0 | `check_duplicate_conversions.sql` |
| **U-03** `onboarding_step_completed` once per step per user | `user_pseudo_id + step_index` | `onboarding_step_completed` | >1% of users with duplicate step → WARNING | P1 | Ad hoc |

**Gap classification on duplicate events:**

| Gap between duplicates | Probable cause |
|---|---|
| < 1 000 ms | Race condition in async callback |
| 1 000 – 30 000 ms | Double-tap or missing UI debounce |
| > 30 000 ms | Activity recreation, session replay bug |

Finance uses `transaction_id` for monthly P&L. Duplicates without deduplication inflate reported revenue. The 7.9% Android duplication rate on `claim_submitted` pre-fix came from `OnClickListener` binding — event fired twice on rapid consecutive taps.

---

## CF — Conformity

Values that must match an approved format or enum.

| Rule | Check | Threshold | Severity |
|---|---|---|---|
| **CF-01** Event name is `snake_case` | `REGEXP_CONTAINS(event_name, r'[A-Z\-\s]')` | Any non-conforming event name → WARNING | P1 |
| **CF-02** No deprecated events in production | Name IN (`submit_claim`, `notif_clicked`, `documentUploaded`, `payment_screen_view`, `user_registered`, `step_done`) | Any traffic → WARNING | P1 |
| **CF-03** `auth_method` in approved enum | `email`, `google`, `apple`, `sms` | Any out-of-enum → WARNING | P1 |
| **CF-04** `error_type` in approved enum | `auth_error`, `network_timeout`, `validation_failed`, `server_error`, `permission_denied`, `session_expired`, `file_too_large`, `unsupported_format`, `payment_declined`, `unknown` | >5% out-of-enum → WARNING | P2 |
| **CF-05** `claim_type` in approved enum | `property`, `vehicle`, `health`, `travel` | Any out-of-enum → WARNING | P1 |
| **CF-06** `platform` is `IOS` or `ANDROID` | Firebase-native uppercase values | Any other value → WARNING | P2 |

**CF-04 context:** Before the taxonomy fix, Android `error_type` was free-text. 47 distinct values found including full Java exception class names (`java.net.SocketTimeoutException`) and localised user-facing strings. Cross-platform error analysis was impossible.

---

## T — Timeliness / Volume

Volume anomalies signal dropped events, duplicated data, or tracking breaks before dashboards surface them.

| Rule | Signal | Threshold | Severity |
|---|---|---|---|
| **T-01** `payment_completed` volume anomaly | z-score vs 7-day rolling avg | \|z\| > 2 → WARNING · \|z\| > 3 → CRITICAL | P0 |
| **T-02** `claim_submitted` volume anomaly | z-score vs 7-day rolling avg | \|z\| > 2 → WARNING · \|z\| > 3 → CRITICAL | P0 |
| **T-03** `login_success` sudden drop | Day-over-day % change | > −30% in 1 day → CRITICAL (possible auth outage) | P0 |
| **T-04** BigQuery export freshness | Max `event_timestamp` in latest partition | > 26h since last update → CRITICAL | P0 |
| **T-05** Debug environment events in production | `environment = 'debug'` in production tables | Any count > 0 → WARNING | P1 |

**T-05 failure history:** A staging device running a debug build was briefly connected to the production Firebase project during a load test. 2,300 synthetic `payment_completed` events with `transaction_id = 'test_*'` landed in production BigQuery before the device was removed. Finance noticed the Stripe discrepancy within 2 hours. T-05 was added as a direct result.

---

## CS — Consistency

Cross-event and cross-platform logic that, if broken, indicates implementation gaps or session stitching failures.

| Rule | Check | Threshold | Severity |
|---|---|---|---|
| **CS-01** iOS/Android event volume ratio within baseline | Ratio deviation vs 30-day baseline | > 30% deviation → WARNING · > 50% or one platform at zero → CRITICAL | P0/P1 |
| **CS-02** `claim_submitted` preceded by `claim_started` in session | No orphaned submissions | > 2% orphaned → WARNING | P1 |
| **CS-03** `payment_completed` ≤ `purchase_initiated` count (+5% tolerance) | Count comparison | > 5% excess → WARNING (suggests duplication upstream) | P0 |
| **CS-04** `onboarding_completed` preceded by all 6 `onboarding_step_completed` events | All step_index values present | > 3% of completed sessions missing any step → WARNING | P1 |
| **CS-05** No `payment_completed` and `payment_failed` for same `transaction_id` | Mutual exclusion | Any occurrence → CRITICAL | P0 |

---

## P — Privacy / GDPR

Non-negotiable. Any failure triggers immediate DPO notification.

| Rule | Check | Threshold | Severity |
|---|---|---|---|
| **P-01** No `user_id` set before `consent_granted` in session | `setUserId()` call order vs consent event timestamp | Any occurrence → CRITICAL | P0 |
| **P-02** No custom events before `consent_granted` on first-launch sessions | Custom event timestamp < `consent_granted` timestamp | Any occurrence → CRITICAL | P0 |
| **P-03** `consent_granted` or `consent_declined` fires on first session | `first_open` sessions with neither consent event | > 5% without consent event → WARNING | P0 |
| **P-04** Consent audit trail complete | `consent_source` non-null on all consent events | > 0% null → WARNING | P1 |

**P-02 audit finding:** `app_open` and `claim_draft_saved` were confirmed firing pre-consent on both platforms before v4.11. Root cause: Firebase SDK initialized without `ANALYTICS_STORAGE = DENIED` defaults. Scope: ~340,000 `first_open` events and ~8,200 `claim_draft_saved` events collected without consent. Documented in `gdpr_audit_findings.md`.

---

## Validation Schedule

| Category | Frequency | Output table | Alert channel |
|---|---|---|---|
| C, U, T, CS | Daily 08:30 CET | `dq_alerts.daily_results` | #data-alerts (P0 CRITICAL), #data-quality (P1) |
| CF | Weekly, Monday 09:00 | `dq_alerts.daily_results` | #data-quality |
| P | Weekly + on any consent config change | `dq_alerts.daily_results` | #data-alerts + DPO direct message |

P2 findings are reviewed in the weekly Analytics standup. No automated alert.
