-- funnel_claim_submission.sql
-- Claim submission funnel: claim_started → steps 1-4 → document_uploaded → claim_submitted
-- Scope: last 30 days, authenticated users only (user_id non-null)
-- Deduplication: claim_id is the idempotency key for claim_submitted
-- Known history: pre-v4.12 Android data contains ~7.9% duplicate claim_submitted events
--   caused by OnClickListener binding. Excluded via app_version filter below.
-- Run: daily scheduled query → results feed Looker Studio funnel dashboard (Page 2)

WITH

raw AS (
  SELECT
    user_pseudo_id,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'user_id')        AS user_id,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'claim_id')       AS claim_id,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'claim_type')     AS claim_type,
    (SELECT value.int_value    FROM UNNEST(event_params) WHERE key = 'step_index')     AS step_index,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'has_documents')  AS has_documents,
    platform,
    app_info.version                                                                    AS app_version,
    event_name,
    event_timestamp
  FROM `project.analytics_XXXXXXX.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY))
                      AND FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY))
    AND event_name IN (
      'claim_started',
      'claim_step_completed',
      'document_uploaded',
      'claim_submitted'
    )
    AND (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'user_id') IS NOT NULL
    -- Exclude pre-fix Android versions with known duplication bug
    AND NOT (platform = 'ANDROID' AND app_info.version < '4.12')
),

-- One row per claim attempt, keyed on claim_id when available.
-- A session without claim_id (claim_started before API assigns it) falls back to user_pseudo_id.
-- This correctly handles abandoned sessions that never reached a server-assigned claim_id.
per_claim AS (
  SELECT
    COALESCE(MAX(claim_id), user_pseudo_id)                                           AS claim_key,
    MAX(user_id)                                                                       AS user_id,
    MAX(platform)                                                                      AS platform,
    MAX(claim_id)                                                                      AS claim_id,
    MAX(claim_type)                                                                    AS claim_type,
    MAX(has_documents)                                                                 AS has_documents,

    MAX(CASE WHEN event_name = 'claim_started'                             THEN 1 END) AS did_start,
    MAX(CASE WHEN event_name = 'claim_step_completed' AND step_index = 1   THEN 1 END) AS did_step_1,
    MAX(CASE WHEN event_name = 'claim_step_completed' AND step_index = 2   THEN 1 END) AS did_step_2,
    MAX(CASE WHEN event_name = 'claim_step_completed' AND step_index = 3   THEN 1 END) AS did_step_3,
    MAX(CASE WHEN event_name = 'claim_step_completed' AND step_index = 4   THEN 1 END) AS did_step_4,
    MAX(CASE WHEN event_name = 'document_uploaded'                         THEN 1 END) AS did_upload,
    MAX(CASE WHEN event_name = 'claim_submitted'                           THEN 1 END) AS did_submit,

    MIN(CASE WHEN event_name = 'claim_started'   THEN event_timestamp END)             AS ts_started,
    MIN(CASE WHEN event_name = 'claim_submitted' THEN event_timestamp END)             AS ts_submitted
  FROM raw
  GROUP BY user_pseudo_id, COALESCE(
    (SELECT value.string_value FROM UNNEST((SELECT event_params FROM raw r2 WHERE r2.user_pseudo_id = raw.user_pseudo_id LIMIT 1)) WHERE key = 'claim_id'),
    user_pseudo_id
  )
),

-- Deduplicate claim_submitted: keep only the first occurrence per claim_id.
-- Residual duplicates post-v4.12 (0.2%) are network-retry edge cases, not implementation bugs.
deduped AS (
  SELECT
    *,
    ROW_NUMBER() OVER (PARTITION BY claim_id ORDER BY ts_submitted) AS rn
  FROM per_claim
  WHERE claim_id IS NOT NULL
),

-- Re-union deduped (claim_id present) with abandoned sessions (no claim_id, never submitted)
combined AS (
  SELECT * EXCEPT(rn) FROM deduped WHERE rn = 1
  UNION ALL
  SELECT * FROM per_claim WHERE claim_id IS NULL
),

funnel AS (
  SELECT
    platform,
    claim_type,

    COUNT(*)                        AS started,
    COUNTIF(did_step_1 = 1)         AS step_1,
    COUNTIF(did_step_2 = 1)         AS step_2,
    COUNTIF(did_step_3 = 1)         AS step_3,
    COUNTIF(did_step_4 = 1)         AS step_4,
    COUNTIF(did_upload = 1)         AS uploaded,
    COUNTIF(did_submit = 1)         AS submitted,

    -- Step-to-step conversion rates (sequential, not vs started)
    ROUND(SAFE_DIVIDE(COUNTIF(did_step_1 = 1), COUNT(*))                       * 100, 1) AS cvr_start_to_s1,
    ROUND(SAFE_DIVIDE(COUNTIF(did_step_2 = 1), COUNTIF(did_step_1 = 1))        * 100, 1) AS cvr_s1_to_s2,
    ROUND(SAFE_DIVIDE(COUNTIF(did_step_3 = 1), COUNTIF(did_step_2 = 1))        * 100, 1) AS cvr_s2_to_s3,
    ROUND(SAFE_DIVIDE(COUNTIF(did_step_4 = 1), COUNTIF(did_step_3 = 1))        * 100, 1) AS cvr_s3_to_s4,
    ROUND(SAFE_DIVIDE(COUNTIF(did_upload = 1), COUNTIF(did_step_4 = 1))        * 100, 1) AS cvr_s4_to_upload,
    ROUND(SAFE_DIVIDE(COUNTIF(did_submit = 1), COUNTIF(did_upload = 1))        * 100, 1) AS cvr_upload_to_submit,

    -- End-to-end: claim_started → claim_submitted
    ROUND(SAFE_DIVIDE(COUNTIF(did_submit = 1), COUNT(*))                       * 100, 1) AS overall_cvr,

    -- Time-to-submit distribution (microseconds → minutes)
    ROUND(APPROX_QUANTILES(SAFE_DIVIDE(ts_submitted - ts_started, 60000000), 100)[OFFSET(25)], 1) AS p25_minutes,
    ROUND(APPROX_QUANTILES(SAFE_DIVIDE(ts_submitted - ts_started, 60000000), 100)[OFFSET(50)], 1) AS p50_minutes,
    ROUND(APPROX_QUANTILES(SAFE_DIVIDE(ts_submitted - ts_started, 60000000), 100)[OFFSET(90)], 1) AS p90_minutes,

    -- Document upload rate among submitted claims (proxy for claim complexity)
    ROUND(SAFE_DIVIDE(COUNTIF(did_submit = 1 AND did_upload = 1), COUNTIF(did_submit = 1)) * 100, 1) AS pct_submitted_with_docs

  FROM combined
  WHERE did_start = 1
  GROUP BY platform, claim_type
),

-- Attach alert flags directly in the output.
-- Thresholds derived from 90-day baseline (Jul–Sep 2025, post-fix data only).
-- P0: overall_cvr drop signals broken funnel or product regression — escalate same day.
-- P1: single-step drop ≥ 10pp vs baseline — investigate within 3 days.
-- P2: time-to-submit p90 spike — UX signal, no urgent action required.
flagged AS (
  SELECT
    *,
    CASE
      WHEN overall_cvr    < 55.0  THEN 'P0 — overall conversion below 55% (baseline 64%)'
      WHEN cvr_s2_to_s3   < 72.0  THEN 'P1 — step 2→3 drop-off below 72% (baseline 82%)'
      WHEN cvr_s3_to_s4   < 74.0  THEN 'P1 — step 3→4 drop-off below 74% (baseline 84%)'
      WHEN cvr_upload_to_submit < 85.0 THEN 'P1 — upload→submit drop below 85% (baseline 93%)'
      WHEN p90_minutes    > 45.0  THEN 'P2 — p90 time-to-submit above 45 min (baseline 28 min)'
      ELSE NULL
    END AS alert_flag
  FROM funnel
)

SELECT
  platform,
  claim_type,
  started,
  step_1,
  step_2,
  step_3,
  step_4,
  uploaded,
  submitted,
  cvr_start_to_s1,
  cvr_s1_to_s2,
  cvr_s2_to_s3,
  cvr_s3_to_s4,
  cvr_s4_to_upload,
  cvr_upload_to_submit,
  overall_cvr,
  p25_minutes,
  p50_minutes,
  p90_minutes,
  pct_submitted_with_docs,
  alert_flag
FROM flagged
ORDER BY
  CASE WHEN alert_flag LIKE 'P0%' THEN 1 WHEN alert_flag LIKE 'P1%' THEN 2 ELSE 3 END,
  platform,
  claim_type
