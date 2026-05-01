# Results

The PM had been presenting an inflated Android conversion rate to the exec team for 8 months. This project is what happened when someone finally ran the SQL.

**Period:** July 2025 (pre-fix baseline) → November 2025 (6 weeks post v4.13 rollout)  
**Data source:** BigQuery, Stripe reconciliation, Commanders Act CRM reports

---

## Revenue & Finance

| Metric | Before | After |
|---|---|---|
| Revenue discrepancy — BigQuery vs Stripe | **34%** | **1.2%** |
| Monthly revenue undercount in analytics | **€41,200** | **€1,480** |
| Finance escalations due to data discrepancy | **3 in Q3 2025** | **0 in Q4 2025** |

The 34% gap had three compounding causes: `transaction_id` null on 12.4% of Android payments (no Stripe deduplication possible), `payment_completed` duplicated on Android (inflated count), and `purchase_initiated` missing entirely on Android (funnel broken from the top). Finance had flagged the gap but couldn't explain it.

---

## Data Quality

| Metric | Before | After |
|---|---|---|
| `transaction_id` null rate — `payment_completed` Android | **12.4%** | **0.0%** |
| `claim_submitted` duplication rate — Android | **7.9%** | **0.2%** |
| `user_id` null rate — P0 post-auth events Android | **8.3%** | **0.1%** |
| Events with non-compliant naming in production | **17** | **0** |
| Cross-platform event parity — P0/P1 events | **63%** | **96%** |
| Daily validation rule pass rate | not measured | **97.4%** |

---

## Product & Funnel Accuracy

| Metric | Before | After |
|---|---|---|
| Android claim conversion rate (reported) | **71%** | **64%** — corrected, not a regression |
| Android claim conversion rate (true) | **unknown** | **64%** — baseline established |
| `document_uploaded` visible on Android | **0%** — event missing | **78%** completion rate |
| A/B tests invalidated by `filter_applied` overcounting | **2** | **0** |

The Android conversion rate dropped 7pp after the fix. This was not a product problem — it was the removal of 7.9% duplicate `claim_submitted` events that had been inflating the denominator. Product had been optimizing against a false baseline.

---

## Marketing & CRM

| Metric | Before | After |
|---|---|---|
| Android re-engagement audience size | **41,200** | **32,100** — was inflated by naming mismatch |
| Android push attribution accuracy | **broken** | **restored** |
| CRM `user_id` match rate post-login | **91.7%** | **99.9%** |
| Onboarding step 4 CRM trigger (payment method) | **not firing** | **active** |

Android push campaign attribution had been broken for 6+ months due to `notif_clicked` vs `notification_opened` naming split. Marketing had attributed the gap to "Android users being less responsive to push." That conclusion was wrong and had affected budget allocation for two quarters.

---

## GDPR / Legal

| Metric | Before | After |
|---|---|---|
| Event types collecting data pre-consent | **4** | **0** |
| Pre-consent `first_open` events in BigQuery | **~340,000** | **0 (ongoing)** |
| Consent audit trail in BigQuery | **none** | **full trail** |
| Sessions with consent event before any custom event | **~0%** | **99.8%** |
| Open DPO compliance actions | **6** | **1** — `session_start` legal review pending |

---

## Operational

| Metric | Before | After |
|---|---|---|
| Data engineer time on incident investigation | **~40% of week** | **~8% of week** |
| Mean time to resolve a P0 data quality incident | **3–5 days** | **< 4 hours** |
| Finance escalations requiring analytics investigation | **3 in Q3** | **0 in Q4** |
