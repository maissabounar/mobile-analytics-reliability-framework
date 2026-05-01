# GDPR Compliance — Firebase Analytics + Commanders Act

**Owner:** Analytics + DPO  
**CMP:** Commanders Act (TCF 2.2) · **Firebase SDK:** Analytics 21.3+ (consent mode v2)  
**Audit period:** Aug–Sep 2025 · **All critical findings resolved:** v4.11 (2025-09-22)

---

## Audit Findings

Four critical violations identified. Root cause in every case: Firebase initialized without `ANALYTICS_STORAGE = DENIED` defaults — the SDK does not default to denied.

| Finding | Event(s) | Scope | Status |
|---|---|---|---|
| Auto-collected events before consent | `app_open`, `first_open`, `session_start` | ~340,000 events, all installs pre-v4.11 | Resolved v4.11 |
| Custom event before consent | `claim_draft_saved` | ~8,200 events, first-launch sessions | Resolved v4.11 |
| No consent audit trail | — | No `consent_granted`/`consent_declined` event existed | Resolved v4.11 |
| Consent state not restored on relaunch | — | ~300ms gap between SDK init and CMP restore on returning users | Resolved v4.11 |
| `session_start` pre-consent status | `session_start` | Under external legal review | Open — Q4 2025 |

Pre-v4.11 BigQuery data containing pre-consent events cannot be retroactively deleted (row-level deletion not supported in Firebase export). Documented in Article 30 records.

---

## Implementation

### 1. Default Deny — Must run before Firebase SDK initialization

**Android** (`Application.onCreate()`):
```kotlin
val denyAll = mapOf(
    FirebaseAnalytics.ConsentType.ANALYTICS_STORAGE    to FirebaseAnalytics.ConsentStatus.DENIED,
    FirebaseAnalytics.ConsentType.AD_STORAGE           to FirebaseAnalytics.ConsentStatus.DENIED,
    FirebaseAnalytics.ConsentType.AD_USER_DATA         to FirebaseAnalytics.ConsentStatus.DENIED,
    FirebaseAnalytics.ConsentType.AD_PERSONALIZATION   to FirebaseAnalytics.ConsentStatus.DENIED
)
Firebase.analytics.setConsent(denyAll)
// FirebaseApp.initializeApp() after this line only
```

**iOS** (`AppDelegate.application(_:didFinishLaunchingWithOptions:)`):
```swift
Analytics.setConsent([
    .analyticsStorage:   .denied,
    .adStorage:          .denied,
    .adUserData:         .denied,
    .adPersonalization:  .denied
])
FirebaseApp.configure()   // after setConsent, not before
```

### 2. CMP Callback — Apply Consent After User Interaction

**Android:**
```kotlin
CommandersActCMP.setOnConsentUpdatedListener { consent ->
    val analytics = if (consent.hasCategory("analytics")) GRANTED else DENIED
    val ads       = if (consent.hasCategory("advertising")) GRANTED else DENIED

    Firebase.analytics.setConsent(mapOf(
        FirebaseAnalytics.ConsentType.ANALYTICS_STORAGE  to analytics,
        FirebaseAnalytics.ConsentType.AD_STORAGE         to ads,
        FirebaseAnalytics.ConsentType.AD_USER_DATA       to ads,
        FirebaseAnalytics.ConsentType.AD_PERSONALIZATION to ads
    ))
    Firebase.analytics.logEvent(
        if (analytics == GRANTED) "consent_granted" else "consent_declined",
        bundleOf(
            "consent_analytics"  to if (analytics == GRANTED) "granted" else "denied",
            "consent_marketing"  to if (ads == GRANTED) "granted" else "denied",
            "consent_source"     to "first_launch"
        )
    )
}
```

**iOS:**
```swift
CommandersActCMP.shared.onConsentUpdated = { consent in
    let analytics: Analytics.ConsentStatus = consent.hasCategory("analytics") ? .granted : .denied
    let ads: Analytics.ConsentStatus       = consent.hasCategory("advertising") ? .granted : .denied

    Analytics.setConsent([
        .analyticsStorage: analytics, .adStorage: ads,
        .adUserData: ads,             .adPersonalization: ads
    ])
    Analytics.logEvent(
        analytics == .granted ? "consent_granted" : "consent_declined",
        parameters: [
            "consent_analytics": analytics == .granted ? "granted" : "denied",
            "consent_marketing": ads == .granted ? "granted" : "denied",
            "consent_source":    "first_launch"
        ]
    )
}
```

### 3. Returning User — Restore Consent Before Any Event Fires

```kotlin
// Android — Application.onCreate(), before any event can fire
Firebase.analytics.setConsent(denyAll)                 // always start denied
CommandersActCMP.getStoredConsent()?.let { stored ->
    applyConsentToFirebase(stored)                      // synchronous — no coroutine
}
```

```swift
// iOS — before FirebaseApp.configure()
Analytics.setConsent(denyAll)
if let stored = CommandersActCMP.shared.storedConsent {
    applyConsentToFirebase(stored)
}
FirebaseApp.configure()
```

### 4. All Custom Events — Consent Guard

```kotlin
fun logEvent(name: String, params: Bundle) {
    if (!consentManager.isAnalyticsGranted()) return
    firebaseAnalytics.logEvent(name, params)
}
```

---

## Validation Rules

| Rule | Check | Threshold | Severity |
|---|---|---|---|
| **P-01** No custom event before `consent_granted` | `MIN(custom_event_ts) < consent_ts` on first-open sessions | Any occurrence → CRITICAL | P0 |
| **P-02** No `user_id` set before consent | `setUserId` precedes `consent_granted` | Any occurrence → CRITICAL | P0 |
| **P-03** Consent event on every first session | `first_open` with no consent event same day | > 5% → WARNING | P0 |
| **P-04** `consent_source` non-null | All consent events | Any null → WARNING | P1 |

**BigQuery — P-01 check (runs weekly and after any consent config change):**
```sql
WITH first_open_sessions AS (
  SELECT
    user_pseudo_id,
    MIN(CASE WHEN event_name = 'first_open'      THEN event_timestamp END) AS ts_first_open,
    MIN(CASE WHEN event_name = 'consent_granted' THEN event_timestamp END) AS ts_consent,
    MIN(CASE WHEN event_name NOT IN (
        'first_open','consent_granted','consent_declined',
        'app_open','session_start','screen_view'
      ) THEN event_timestamp END)                                           AS ts_first_custom
  FROM `project.analytics_XXXXXXX.events_*`
  WHERE _TABLE_SUFFIX = FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY))
  GROUP BY user_pseudo_id
  HAVING ts_first_open IS NOT NULL
)
SELECT
  COUNT(*)                                                            AS new_installs,
  COUNTIF(ts_first_custom < ts_consent)                              AS pre_consent_violations,
  COUNTIF(ts_consent IS NULL AND ts_first_custom IS NOT NULL)        AS missing_consent_event,
  ROUND(COUNTIF(ts_first_custom < ts_consent) / COUNT(*) * 100, 2)  AS violation_rate_pct
FROM first_open_sessions
```

Any non-zero `pre_consent_violations` → P0 incident. Notify DPO within 1 hour.

---

## Pre-Consent Policy — Quick Reference

| Permitted before consent | Not permitted before consent |
|---|---|
| Firebase SDK init (deny-all defaults) | Any custom Firebase event |
| Commanders Act CMP render | `setUserId()` |
| Reading stored TCF string | Auto-collected events (`app_open`, `first_open`) — blocked by deny-all |
| Crash reporting (non-identifying) | Push token registration |
| Client-side A/B assignment (no server call) | CRM profile creation or update |
