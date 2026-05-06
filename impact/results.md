# Results

This project improved mobile analytics reliability across iOS and Android.

Several events were incomplete, duplicated, or inconsistent across platforms. This affected conversion reporting, CRM activation, funnel analysis, and consent monitoring.

**Period:** July 2025 baseline → November 2025, 6 weeks after v4.13 rollout  
**Data sources:** BigQuery, payment reconciliation exports, CRM reporting, mobile analytics events

---

## Executive Summary

| Area | Before | After |
|---|---:|---:|
| Payment reconciliation gap | 34% | 1.2% |
| Android `transaction_id` null rate | 12.4% | 0.0% |
| Android `claim_submitted` duplication rate | 7.9% | 0.2% |
| Cross-platform event parity for P0/P1 events | 63% | 96% |
| CRM post-login user match rate | 91.7% | 99.9% |
| Daily validation rule pass rate | Not measured | 97.4% |
| P0 issue resolution time | 3–5 days | < 4 hours |

> [!NOTE]
> The main impact was the shift from reactive debugging to monitored data reliability.

---

## Business Reporting

| Metric | Before | After |
|---|---:|---:|
| Payment discrepancy between analytics and payment records | 34% | 1.2% |
| Estimated monthly revenue gap in analytics | €41 200 | €1 480 |
| Sales reporting escalations linked to data discrepancies | 3 in Q3 2025 | 0 in Q4 2025 |

Main issues found:

- Missing `transaction_id` on Android payments
- Duplicate `payment_completed` events
- Missing `purchase_initiated` events on Android
- Inconsistent event naming between iOS and Android

---

## Data Quality

| Metric | Before | After |
|---|---:|---:|
| Android `transaction_id` null rate | 12.4% | 0.0% |
| Android `claim_submitted` duplication rate | 7.9% | 0.2% |
| Android `user_id` null rate on post-auth P0 events | 8.3% | 0.1% |
| Non-compliant event names in production | 17 | 0 |
| Cross-platform parity for P0/P1 events | 63% | 96% |
| Daily validation rule pass rate | Not measured | 97.4% |

What improved:

- Required business keys are checked daily
- Duplicate conversions are detected before reporting
- Deprecated events are monitored in production
- iOS and Android tracking coverage is compared automatically

---

## Product and Funnel Accuracy

| Metric | Before | After |
|---|---:|---:|
| Android claim conversion rate, reported | 71% | 64% |
| Android claim conversion rate, validated baseline | Unknown | 64% |
| Android `document_uploaded` tracking coverage | 0%, event missing | 78% |
| A/B tests affected by overcounted events | 2 | 0 |

> [!IMPORTANT]
> The drop from 71% to 64% was a measurement correction, not a product regression.

The corrected 64% rate became the trusted baseline for funnel analysis, roadmap decisions, and experimentation.

---

## CRM and Lifecycle Activation

| Metric | Before | After |
|---|---:|---:|
| Android re-engagement audience size | 41 200 | 32 100 |
| Android push attribution | Broken | Restored |
| CRM `user_id` match rate after login | 91.7% | 99.9% |
| Onboarding step 4 CRM trigger | Not firing | Active |

The main issue was an event naming split between Android and iOS:

- `notif_clicked`
- `notification_opened`

After the taxonomy fix, push attribution and lifecycle triggers were rebuilt on stable events.

---

## Privacy and Consent Monitoring

| Metric | Before | After |
|---|---:|---:|
| Event types firing before consent | 4 | 0 |
| Pre-consent `first_open` events in BigQuery | ~340 000 historical records | 0 ongoing |
| Consent audit trail in BigQuery | Not available | Available |
| Sessions with consent captured before custom events | ~0% | 99.8% |
| Open privacy follow-up actions | 6 | 1 |

Consent checks were added to monitor whether custom events fired before consent.

Analytics storage is now denied by default until the user makes a consent choice.

---

## Operational Impact

| Metric | Before | After |
|---|---:|---:|
| Data engineering time spent on incident investigation | ~40% of weekly time | ~8% |
| P0 data quality resolution time | 3–5 days | < 4 hours |
| Sales reporting escalations requiring analytics investigation | 3 in Q3 2025 | 0 in Q4 2025 |

P0 issues are now detected through daily validation checks with clear owners, severity levels, and SQL references.

---

## Final Outcome

This project created a cleaner mobile analytics foundation.

Teams now have a clearer view of:

- Which events are trusted
- Which metrics are affected by tracking gaps
- Which issues need escalation
- Which conversion baselines are safe to use
