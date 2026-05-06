# GDPR Compliance

**Owner:** Analytics + Privacy  
**CMP:** Commanders Act  
**Firebase SDK:** Analytics 21.3+  
**Audit period:** Aug–Sep 2025  
**Critical fixes released:** v4.11, 2025-09-22

This document explains how consent is handled for Firebase Analytics events collected through the mobile app.

The goal is simple: no analytics event should be collected before the user’s consent status is known.

---

## Summary

Before v4.11, Firebase Analytics was initialized before consent defaults were applied.

This created a short window where some events were collected before consent.

The fix introduced:

- Denied-by-default Firebase consent settings
- Consent restore before event tracking
- Consent events in BigQuery
- Guards around all custom events
- Weekly privacy validation checks

> [!IMPORTANT]
> Analytics storage must be denied by default before Firebase starts collecting events.

---

## Audit Findings

| Finding | Scope | Status |
|---|---:|---|
| Auto-collected events before consent | ~340 000 historical events | Resolved in v4.11 |
| Custom events before consent | ~8 200 historical events | Resolved in v4.11 |
| Missing consent audit trail | No consent events available in BigQuery | Resolved in v4.11 |
| Consent state not restored fast enough on relaunch | Short gap before CMP restore | Resolved in v4.11 |
| `session_start` pre-consent review | Under privacy review | Open |

Historical pre-consent events are kept in audit documentation. Ongoing collection is blocked by the new consent setup.

---

## Consent Implementation

### 1. Deny by Default

Firebase consent must be denied before any analytics event is allowed.

Expected default state:

```text
ANALYTICS_STORAGE = DENIED
AD_STORAGE = DENIED
AD_USER_DATA = DENIED
AD_PERSONALIZATION = DENIED
```

---

### 2. Apply Consent After CMP Choice

When the user accepts or declines consent in Commanders Act, the app updates Firebase consent settings.

Expected events:

| User choice | Event |
|---|---|
| Analytics accepted | `consent_granted` |
| Analytics declined | `consent_declined` |

Required consent parameters:

| Parameter | Example |
|---|---|
| `consent_analytics` | `granted` |
| `consent_marketing` | `denied` |
| `consent_source` | `first_launch` |

---

### 3. Restore Consent for Returning Users

For returning users, stored consent must be restored before any event fires.

Expected flow:

1. Start Firebase consent as denied
2. Read stored Commanders Act consent
3. Apply stored consent to Firebase
4. Allow analytics events only if consent is granted

---

### 4. Guard Custom Events

All custom tracking must pass through a consent guard.

Expected logic:

```text
If analytics consent is granted:
  log event

If analytics consent is denied or unknown:
  do not log event
```

---

## Validation Rules

| Rule | Check | Threshold | Severity |
|---|---|---:|---|
| **P-01** No custom event before `consent_granted` | First custom event timestamp < consent timestamp | 0 allowed | P0 |
| **P-02** No `user_id` before consent | User ID set before consent | 0 allowed | P0 |
| **P-03** Consent event captured on first session | Missing `consent_granted` or `consent_declined` | >5% warning | P0 |
| **P-04** `consent_source` populated | Null consent source | >0% warning | P1 |

> [!IMPORTANT]
> Any P0 privacy issue must be reviewed by Analytics and Privacy.

---

## BigQuery Validation

Weekly check: no custom event before consent on first-open sessions.

```sql
WITH first_open_sessions AS (
  SELECT
    user_pseudo_id,
    MIN(CASE WHEN event_name = 'first_open' THEN event_timestamp END) AS ts_first_open,
    MIN(CASE WHEN event_name IN ('consent_granted', 'consent_declined') THEN event_timestamp END) AS ts_consent,
    MIN(CASE
      WHEN event_name NOT IN (
        'first_open',
        'consent_granted',
        'consent_declined',
        'app_open',
        'session_start',
        'screen_view'
      )
      THEN event_timestamp
    END) AS ts_first_custom_event
  FROM `project.analytics_XXXXXXX.events_*`
  WHERE _TABLE_SUFFIX = FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY))
  GROUP BY user_pseudo_id
  HAVING ts_first_open IS NOT NULL
)

SELECT
  COUNT(*) AS new_installs,
  COUNTIF(ts_first_custom_event < ts_consent) AS pre_consent_custom_events,
  COUNTIF(ts_consent IS NULL AND ts_first_custom_event IS NOT NULL) AS missing_consent_event,
  ROUND(
    SAFE_DIVIDE(COUNTIF(ts_first_custom_event < ts_consent), COUNT(*)) * 100,
    2
  ) AS violation_rate_pct
FROM first_open_sessions;
```

Expected result:

| Metric | Expected value |
|---|---:|
| `pre_consent_custom_events` | 0 |
| `missing_consent_event` | 0 or within accepted threshold |
| `violation_rate_pct` | 0.00 |

---

## Pre-Consent Policy

| Allowed before consent | Not allowed before consent |
|---|---|
| CMP display | Custom analytics events |
| Reading stored consent | `setUserId()` |
| Firebase init with denied defaults | CRM profile update |
| Non-identifying crash reporting | Push token registration |
| Local-only A/B assignment | Revenue or claim tracking |

---

## Final Rule

No custom analytics event should fire before consent is granted.

If consent is declined or unknown, tracking must stay disabled.
