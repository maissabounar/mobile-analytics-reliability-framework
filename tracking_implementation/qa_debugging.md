# QA & Debugging

---

## Tools

| Tool | Used for |
|---|---|
| **Analytics Debugger** (Chrome extension) | Real-time dataLayer inspection — validates payload structure on each interaction |
| **Firebase DebugView** | Mobile event validation — confirms event name, parameters, and trigger timing |
| **BigQuery** | Post-release validation — null rates, duplicates, funnel integrity, platform parity |

---

## Real-Time Validation

**Analytics Debugger**
- Intercept each `dataLayer.push()` on the target page
- Confirm event name matches taxonomy (`snake_case`, no deprecated names)
- Confirm all required parameters are present and non-empty
- Confirm `transaction_id` / `claim_id` come from server response, not client-generated values

**Firebase DebugView**
```bash
# Android
adb shell setprop debug.firebase.analytics.app com.example.myapp

# iOS — add to Xcode scheme launch arguments
-FIRAnalyticsDebugEnabled
```
- Verify event fires **after** API response, not on button tap
- Verify no event fires before `consent_granted` on fresh install
- Verify no duplicate event on double-tap or activity recreation (Android)

---

## Event Validity Rule

An event is considered **valid** if and only if:

1. All required parameters are present and non-empty
2. The trigger fired after server confirmation (not a UI action)
3. `user_id` is set before the event fires
4. Consent state is `ANALYTICS_STORAGE = GRANTED`
5. No duplicate exists for the same business key (`transaction_id` or `claim_id`) within the session

If any condition fails, the event must be blocked — not sent with partial data.

---

## Payload Validation Checklist

Before marking an event as QA-passed:

- [ ] Event name matches `approved_event_list.csv`
- [ ] All required parameters non-null (see `taxonomy/parameter_dictionary.md`)
- [ ] Enum values in approved set (`claim_type`, `payment_method`, `auth_method`)
- [ ] `amount` is a float in major currency units, not cents
- [ ] `env` is `"production"` — no debug events leaking to prod (see T-05 in `validation_rules.md`)

---

## Post-Release Validation (BigQuery)

Run within 24–48h of rollout, once sufficient volume has accumulated.

```sql
-- Null rate on P0 identifiers — threshold: 0% on transaction_id, claim_id
-- See: sql/validation_suite.sql → CHECK 1

-- Duplicate conversions — any duplicate is a P0 incident
-- See: sql/validation_suite.sql → CHECK 2

-- Platform parity — flag if iOS/Android ratio deviates >30% from baseline
-- See: sql/validation_suite.sql → CHECK 4
```

**Funnel sanity check:** run `sql/analysis/funnel_claim_submission.sql` and verify:
- `overall_cvr` within ±5pp of pre-release baseline
- No `alert_flag` set to `P0` in output

---

## Reconciliation vs Backend

| Signal | Source | Acceptable gap |
|---|---|---|
| `payment_completed` count | BigQuery vs Stripe dashboard | < 2% |
| `claim_submitted` count | BigQuery vs claims API count | < 1% |
| `transaction_id` match rate | BigQuery JOIN to Stripe export | > 99% |

A gap above threshold is treated as a P0 data quality incident regardless of whether the tracking looks correct in DebugView. DebugView confirms implementation. BigQuery confirms production accuracy.
