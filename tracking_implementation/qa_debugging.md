# QA & Debugging

Checklist used to validate mobile analytics events before and after release.

Goal: confirm that events fire at the right time, with the right parameters, and only when consent allows tracking.

---

## Tools

| Tool | Used for |
|---|---|
| Analytics Debugger for Apps | Inspect client-side tracking payloads |
| Firebase DebugView | Validate mobile events in real time |
| BigQuery | Check production data after release |

---

## Real-Time QA

Check that:

- Event name exists in `taxonomy/approved_event_list.csv`
- Event uses `snake_case`
- Deprecated event names are not used
- Required parameters are present
- Enum values match the approved taxonomy
- `transaction_id` and `claim_id` come from server or provider responses
- Event fires after backend confirmation
- Event does not fire before consent
- Event does not duplicate on double tap, retry, or activity recreation

---

## Firebase DebugView Setup

Android:

`adb shell setprop debug.firebase.analytics.app com.example.myapp`

iOS:

`-FIRAnalyticsDebugEnabled`

---

## Event Validity Rule

An event is valid only if:

- Required parameters are present and non-empty
- Trigger timing matches the event definition
- `user_id` is available for post-auth events
- Analytics consent is granted
- No duplicate exists for the same business key in the session

> [!IMPORTANT]
> If a P0 event is missing a required business key, block it. Do not send partial conversion or revenue events.

---

## Payload Checklist

Before marking an event as QA-passed:

- [ ] Event name exists in `taxonomy/approved_event_list.csv`
- [ ] Required parameters exist in `taxonomy/parameter_dictionary.md`
- [ ] Enum values match the approved list
- [ ] `amount` is sent as `49.99`, not `4999`
- [ ] `environment` is correct
- [ ] No debug or staging event is sent to production
- [ ] Consent state is valid before the event fires

---

## Post-Release Validation

Run BigQuery checks within 24–48h after rollout.

| Check | Expected result |
|---|---:|
| Null rate on `transaction_id` | 0% |
| Null rate on `claim_id` | 0% |
| Duplicate `payment_completed` by `transaction_id` | 0 |
| Duplicate `claim_submitted` by `claim_id` | 0 |
| Debug events in production | 0 |
| iOS/Android event parity deviation | < 30% vs baseline |

Reference checks:

- `sql/validation_suite.sql`
- `data_quality_framework/validation_rules.md`

---

## Funnel Sanity Check

Run `sql/analysis/funnel_claim_submission.sql`.

Expected results:

- Conversion rate stays within ±5pp of baseline
- No P0 alert is returned
- No sudden platform-level drop appears
- No final conversion exceeds its upstream event volume

> [!NOTE]
> A conversion rate change after a tracking fix is not always a product regression. It may be a corrected measurement baseline.

---

## Reconciliation Checks

| Signal | Source comparison | Accepted gap |
|---|---|---:|
| `payment_completed` count | BigQuery vs payment reconciliation export | < 2% |
| `claim_submitted` count | BigQuery vs claims API count | < 1% |
| `transaction_id` match rate | BigQuery join with payment export | > 99% |

A gap above threshold is treated as a P0 data quality issue.

DebugView confirms the implementation. BigQuery confirms production accuracy.

---

## QA Sign-Off

An event can be marked as QA-passed when:

- Real-time payload is valid
- Trigger timing is correct
- Consent behavior is correct
- BigQuery checks pass after release
- Reconciliation checks stay within threshold
