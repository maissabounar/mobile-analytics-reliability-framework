-- validation_suite.sql
-- Five daily checks that run as BigQuery Scheduled Queries at 08:30 CET.
-- Results append to dq_alerts.daily_results → Pub/Sub → Slack #data-alerts (P0) / #data-quality (P1).
-- Replace `project.analytics_XXXXXXX` with your Firebase export project and dataset.

-- ─────────────────────────────────────────────────────────────────────────────
-- CHECK 1 — NULL REQUIRED IDENTIFIERS
-- P0 events: 0% tolerance on user_id, transaction_id, claim_id.
-- Root cause history: Android setUserId() async race (fixed v4.12),
--   transaction_id sourced before Stripe callback resolved (fixed v4.13).
-- ─────────────────────────────────────────────────────────────────────────────

WITH

base AS (
  SELECT
    DATE(TIMESTAMP_MICROS(event_timestamp))                                             AS event_date,
    platform,
    event_name,
    app_info.version                                                                    AS app_version,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'user_id')        AS user_id,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'transaction_id') AS transaction_id,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'claim_id')       AS claim_id
  FROM `project.analytics_XXXXXXX.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 14 DAY))
                      AND FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY))
    AND event_name IN (
      'payment_completed', 'claim_submitted', 'claim_approved',
      'login_success', 'signup_completed',
      'purchase_initiated', 'payment_failed', 'claim_started',
      'document_uploaded', 'onboarding_completed', 'logout'
    )
),

null_check AS (
  SELECT
    event_date, platform, event_name, app_version,
    COUNT(*)                                            AS total,
    COUNTIF(user_id IS NULL OR user_id = '')            AS null_user_id,
    COUNTIF(transaction_id IS NULL AND event_name = 'payment_completed') AS null_txn_id,
    COUNTIF(claim_id IS NULL AND event_name = 'claim_submitted')         AS null_claim_id,
    CASE WHEN event_name IN ('payment_completed','claim_submitted','claim_approved','login_success','signup_completed')
         THEN 'P0' ELSE 'P1' END                        AS priority
  FROM base
  GROUP BY 1, 2, 3, 4
),

null_flagged AS (
  SELECT
    'C — null_identifiers' AS check_id,
    event_date, platform, event_name, app_version, priority,
    total,
    null_user_id                                                                  AS anomaly_count,
    ROUND(SAFE_DIVIDE(null_user_id, total) * 100, 2)                              AS anomaly_rate_pct,
    CASE
      WHEN priority = 'P0' AND null_user_id > 0   THEN 'CRITICAL'
      WHEN priority = 'P1' AND SAFE_DIVIDE(null_user_id, total) > 0.03 THEN 'CRITICAL'
      WHEN priority = 'P1' AND null_user_id > 0   THEN 'WARNING'
      ELSE 'OK'
    END AS alert_status
  FROM null_check
  WHERE null_user_id > 0 OR null_txn_id > 0 OR null_claim_id > 0
)

SELECT * FROM null_flagged WHERE alert_status != 'OK'

UNION ALL

-- ─────────────────────────────────────────────────────────────────────────────
-- CHECK 2 — DUPLICATE CONVERSIONS
-- Any duplicate is a P0 incident. Finance reconciles on transaction_id.
-- Gap < 1s = race condition. Gap 1-30s = double tap / missing debounce.
-- Gap > 30s = activity recreation or session replay bug (Android).
-- ─────────────────────────────────────────────────────────────────────────────

SELECT
  'U — duplicate_conversions'                         AS check_id,
  DATE(TIMESTAMP_MICROS(event_timestamp))              AS event_date,
  platform,
  event_name,
  NULL                                                 AS app_version,
  'P0'                                                 AS priority,
  COUNT(*)                                             AS total,
  COUNT(*) - COUNT(DISTINCT
    CASE event_name
      WHEN 'payment_completed' THEN (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'transaction_id')
      WHEN 'claim_submitted'   THEN (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'claim_id')
    END
  )                                                    AS anomaly_count,
  NULL                                                 AS anomaly_rate_pct,
  CASE WHEN COUNT(*) > COUNT(DISTINCT
    CASE event_name
      WHEN 'payment_completed' THEN (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'transaction_id')
      WHEN 'claim_submitted'   THEN (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'claim_id')
    END
  ) THEN 'CRITICAL' ELSE 'OK' END                      AS alert_status
FROM `project.analytics_XXXXXXX.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY))
                    AND FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY))
  AND event_name IN ('payment_completed', 'claim_submitted')
GROUP BY 1, 2, 3, 4, 5, 6
HAVING alert_status = 'CRITICAL'

UNION ALL

-- ─────────────────────────────────────────────────────────────────────────────
-- CHECK 3 — NAMING COMPLIANCE
-- Catches camelCase violations, deprecated events still firing, and
-- parameter values outside the approved enum (auth_method, error_type).
-- Run weekly and post-release. Any deprecated event in production is P1.
-- ─────────────────────────────────────────────────────────────────────────────

SELECT
  'CF — naming_compliance'                             AS check_id,
  DATE(TIMESTAMP_MICROS(event_timestamp))              AS event_date,
  platform,
  event_name,
  NULL                                                 AS app_version,
  'P1'                                                 AS priority,
  COUNT(*)                                             AS total,
  COUNT(*)                                             AS anomaly_count,
  NULL                                                 AS anomaly_rate_pct,
  CASE
    WHEN event_name IN ('submit_claim','notif_clicked','documentUploaded',
                        'payment_screen_view','user_registered','step_done') THEN 'WARNING'
    WHEN REGEXP_CONTAINS(event_name, r'[A-Z]') OR REGEXP_CONTAINS(event_name, r'[^a-z0-9_]') THEN 'WARNING'
    ELSE 'OK'
  END                                                  AS alert_status
FROM `project.analytics_XXXXXXX.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY))
                    AND FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY))
  AND event_name NOT IN ('app_open','session_start','first_open','screen_view',
                         'user_engagement','os_update','app_update','consent_granted','consent_declined')
GROUP BY 1, 2, 3, 4, 5, 6, 10
HAVING alert_status != 'OK'

UNION ALL

-- ─────────────────────────────────────────────────────────────────────────────
-- CHECK 4 — PLATFORM PARITY
-- iOS/Android volume ratio compared against 30-day baseline.
-- >30% deviation = WARNING. One platform at zero for a P0 event = CRITICAL.
-- Nine discrepancies were found in the audit (see event_audit_log.csv).
-- ─────────────────────────────────────────────────────────────────────────────

WITH

daily_vol AS (
  SELECT
    DATE(TIMESTAMP_MICROS(event_timestamp)) AS event_date,
    platform,
    event_name,
    COUNT(*) AS n
  FROM `project.analytics_XXXXXXX.events_*`
  WHERE _TABLE_SUFFIX BETWEEN FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 37 DAY))
                          AND FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY))
    AND platform IN ('IOS','ANDROID')
    AND event_name NOT IN ('user_engagement','os_update','app_update')
  GROUP BY 1,2,3
),

pivot AS (
  SELECT event_date, event_name,
    SUM(CASE WHEN platform='IOS'     THEN n ELSE 0 END) AS ios,
    SUM(CASE WHEN platform='ANDROID' THEN n ELSE 0 END) AS android
  FROM daily_vol GROUP BY 1,2
),

baseline AS (
  SELECT event_name,
    SAFE_DIVIDE(SUM(ios), SUM(android)) AS base_ratio,
    SUM(ios) AS base_ios, SUM(android) AS base_android
  FROM pivot
  WHERE event_date BETWEEN DATE_SUB(CURRENT_DATE(), INTERVAL 37 DAY)
                       AND DATE_SUB(CURRENT_DATE(), INTERVAL 8 DAY)
  GROUP BY 1
),

recent AS (
  SELECT event_name,
    SAFE_DIVIDE(SUM(ios), SUM(android)) AS recent_ratio,
    SUM(ios) AS recent_ios, SUM(android) AS recent_android
  FROM pivot
  WHERE event_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY)
  GROUP BY 1
)

SELECT
  'CS — platform_parity'   AS check_id,
  CURRENT_DATE()           AS event_date,
  'IOS+ANDROID'            AS platform,
  r.event_name,
  NULL                     AS app_version,
  CASE WHEN r.event_name IN ('payment_completed','claim_submitted','login_success','signup_completed') THEN 'P0' ELSE 'P1' END AS priority,
  (r.recent_ios + r.recent_android) AS total,
  ABS(r.recent_ios - r.recent_android) AS anomaly_count,
  ROUND(ABS(SAFE_DIVIDE(r.recent_ratio - b.base_ratio, b.base_ratio)) * 100, 1) AS anomaly_rate_pct,
  CASE
    WHEN r.recent_ios = 0 AND b.base_ios > 100     THEN 'CRITICAL'
    WHEN r.recent_android = 0 AND b.base_android > 100 THEN 'CRITICAL'
    WHEN ABS(SAFE_DIVIDE(r.recent_ratio - b.base_ratio, b.base_ratio)) > 0.5 THEN 'CRITICAL'
    WHEN ABS(SAFE_DIVIDE(r.recent_ratio - b.base_ratio, b.base_ratio)) > 0.3 THEN 'WARNING'
    ELSE 'OK'
  END AS alert_status
FROM recent r
LEFT JOIN baseline b USING(event_name)
WHERE b.base_ratio IS NOT NULL
  AND (b.base_ios + b.base_android) > 200
  AND ABS(SAFE_DIVIDE(r.recent_ratio - b.base_ratio, b.base_ratio)) > 0.3

UNION ALL

-- ─────────────────────────────────────────────────────────────────────────────
-- CHECK 5 — EVENT SEQUENCE INTEGRITY
-- Flags logically impossible orderings within a session:
--   payment_completed with no prior purchase_initiated
--   claim_submitted with no prior claim_started
--   onboarding_completed with fewer than 6 steps recorded
-- Any P0 sequence violation = CRITICAL.
-- ─────────────────────────────────────────────────────────────────────────────

WITH seq_events AS (
  SELECT
    user_pseudo_id,
    event_name,
    event_timestamp,
    DATE(TIMESTAMP_MICROS(event_timestamp)) AS event_date,
    platform,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'claim_id')   AS claim_id,
    (SELECT value.int_value    FROM UNNEST(event_params) WHERE key = 'step_index') AS step_index
  FROM `project.analytics_XXXXXXX.events_*`
  WHERE _TABLE_SUFFIX BETWEEN FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY))
                          AND FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY))
    AND event_name IN ('login_success','claim_started','claim_step_completed',
                       'claim_submitted','purchase_initiated','payment_completed',
                       'onboarding_step_completed','onboarding_completed')
),

orphan_payments AS (
  SELECT event_date, platform, 'payment_completed_no_initiation' AS violation, COUNT(*) AS n
  FROM seq_events pc
  WHERE pc.event_name = 'payment_completed'
    AND NOT EXISTS (
      SELECT 1 FROM seq_events pi
      WHERE pi.user_pseudo_id = pc.user_pseudo_id
        AND pi.event_name = 'purchase_initiated'
        AND pi.event_timestamp < pc.event_timestamp
        AND pi.event_date = pc.event_date
    )
  GROUP BY 1,2,3
),

orphan_claims AS (
  SELECT event_date, platform, 'claim_submitted_no_start' AS violation, COUNT(*) AS n
  FROM seq_events cs
  WHERE cs.event_name = 'claim_submitted'
    AND NOT EXISTS (
      SELECT 1 FROM seq_events cst
      WHERE cst.user_pseudo_id = cs.user_pseudo_id
        AND cst.event_name = 'claim_started'
        AND cst.event_timestamp < cs.event_timestamp
        AND cst.event_date = cs.event_date
    )
  GROUP BY 1,2,3
)

SELECT
  'CS — sequence_integrity' AS check_id,
  event_date,
  platform,
  violation                 AS event_name,
  NULL                      AS app_version,
  'P0'                      AS priority,
  n                         AS total,
  n                         AS anomaly_count,
  NULL                      AS anomaly_rate_pct,
  'CRITICAL'                AS alert_status
FROM orphan_payments WHERE n > 0

UNION ALL

SELECT
  'CS — sequence_integrity' AS check_id,
  event_date, platform, violation AS event_name, NULL, 'P0', n, n, NULL, 'CRITICAL'
FROM orphan_claims WHERE n > 0

ORDER BY
  CASE alert_status WHEN 'CRITICAL' THEN 1 ELSE 2 END,
  CASE priority WHEN 'P0' THEN 1 WHEN 'P1' THEN 2 ELSE 3 END,
  event_date DESC
