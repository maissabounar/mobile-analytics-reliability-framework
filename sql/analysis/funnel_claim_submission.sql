-- funnel_claim_submission.sql
-- Claim submission funnel: claim_started → steps 1-4 → document_uploaded → claim_submitted
-- Scope: last 30 days, authenticated users only
-- Deduplication: claim_id is the idempotency key for claim_submitted
-- Results feed Looker Studio funnel dashboard.
-- Replace `project.analytics_XXXXXXX` with your Firebase export project and dataset.
-- Depending on schema, replace `platform` with `device.operating_system` if needed.

WITH raw AS (
  SELECT
    user_pseudo_id,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'user_id') AS user_id,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'claim_id') AS claim_id,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'claim_type') AS claim_type,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'step_index') AS step_index,
    platform,
    app_info.version AS app_version,
    event_name,
    event_timestamp
  FROM `project.analytics_XXXXXXX.events_*`
  WHERE _TABLE_SUFFIX BETWEEN FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY))
                          AND FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY))
    AND event_name IN (
      'claim_started',
      'claim_step_completed',
      'document_uploaded',
      'claim_submitted'
    )
    AND (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'user_id') IS NOT NULL
),

normalized AS (
  SELECT
    *,
    CONCAT(
      SPLIT(app_version, '.')[SAFE_OFFSET(0)], '.',
      SPLIT(app_version, '.')[SAFE_OFFSET(1)]
    ) AS major_minor_version,

    -- claim_id is not always available at claim_started.
    -- For abandoned claims, fallback keeps them in the funnel.
    COALESCE(claim_id, CONCAT(user_pseudo_id, '-', CAST(DIV(event_timestamp, 1800000000) AS STRING))) AS claim_attempt_key
  FROM raw
  WHERE NOT (
    UPPER(platform) = 'ANDROID'
    AND SAFE_CAST(SPLIT(app_version, '.')[SAFE_OFFSET(0)] AS INT64) = 4
    AND SAFE_CAST(SPLIT(app_version, '.')[SAFE_OFFSET(1)] AS INT64) < 12
  )
),

per_claim AS (
  SELECT
    claim_attempt_key,
    MAX(user_id) AS user_id,
    MAX(platform) AS platform,
    MAX(claim_id) AS claim_id,
    COALESCE(MAX(claim_type), 'unknown') AS claim_type,
    MAX(app_version) AS app_version,

    MAX(CASE WHEN event_name = 'claim_started' THEN 1 ELSE 0 END) AS did_start,
    MAX(CASE WHEN event_name = 'claim_step_completed' AND step_index = 1 THEN 1 ELSE 0 END) AS did_step_1,
    MAX(CASE WHEN event_name = 'claim_step_completed' AND step_index = 2 THEN 1 ELSE 0 END) AS did_step_2,
    MAX(CASE WHEN event_name = 'claim_step_completed' AND step_index = 3 THEN 1 ELSE 0 END) AS did_step_3,
    MAX(CASE WHEN event_name = 'claim_step_completed' AND step_index = 4 THEN 1 ELSE 0 END) AS did_step_4,
    MAX(CASE WHEN event_name = 'document_uploaded' THEN 1 ELSE 0 END) AS did_upload,
    MAX(CASE WHEN event_name = 'claim_submitted' THEN 1 ELSE 0 END) AS did_submit,

    MIN(CASE WHEN event_name = 'claim_started' THEN event_timestamp END) AS ts_started,
    MIN(CASE WHEN event_name = 'claim_submitted' THEN event_timestamp END) AS ts_submitted
  FROM normalized
  GROUP BY claim_attempt_key
),

deduped AS (
  SELECT
    *
  FROM per_claim
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY COALESCE(claim_id, claim_attempt_key)
    ORDER BY ts_submitted NULLS LAST, ts_started
  ) = 1
),

eligible AS (
  SELECT *
  FROM deduped
  WHERE did_start = 1
),

funnel AS (
  SELECT
    UPPER(platform) AS platform,
    claim_type,

    COUNT(*) AS started,
    COUNTIF(did_step_1 = 1) AS step_1,
    COUNTIF(did_step_2 = 1) AS step_2,
    COUNTIF(did_step_3 = 1) AS step_3,
    COUNTIF(did_step_4 = 1) AS step_4,
    COUNTIF(did_upload = 1) AS uploaded,
    COUNTIF(did_submit = 1) AS submitted,

    ROUND(SAFE_DIVIDE(COUNTIF(did_step_1 = 1), COUNT(*)) * 100, 1) AS cvr_start_to_s1,
    ROUND(SAFE_DIVIDE(COUNTIF(did_step_2 = 1), COUNTIF(did_step_1 = 1)) * 100, 1) AS cvr_s1_to_s2,
    ROUND(SAFE_DIVIDE(COUNTIF(did_step_3 = 1), COUNTIF(did_step_2 = 1)) * 100, 1) AS cvr_s2_to_s3,
    ROUND(SAFE_DIVIDE(COUNTIF(did_step_4 = 1), COUNTIF(did_step_3 = 1)) * 100, 1) AS cvr_s3_to_s4,
    ROUND(SAFE_DIVIDE(COUNTIF(did_upload = 1), COUNTIF(did_step_4 = 1)) * 100, 1) AS cvr_s4_to_upload,
    ROUND(SAFE_DIVIDE(COUNTIF(did_submit = 1), COUNTIF(did_upload = 1)) * 100, 1) AS cvr_upload_to_submit,
    ROUND(SAFE_DIVIDE(COUNTIF(did_submit = 1), COUNT(*)) * 100, 1) AS overall_cvr,

    ROUND(APPROX_QUANTILES(
      CASE
        WHEN ts_started IS NOT NULL AND ts_submitted IS NOT NULL
        THEN SAFE_DIVIDE(ts_submitted - ts_started, 60000000)
      END,
      100
    )[OFFSET(25)], 1) AS p25_minutes,

    ROUND(APPROX_QUANTILES(
      CASE
        WHEN ts_started IS NOT NULL AND ts_submitted IS NOT NULL
        THEN SAFE_DIVIDE(ts_submitted - ts_started, 60000000)
      END,
      100
    )[OFFSET(50)], 1) AS p50_minutes,

    ROUND(APPROX_QUANTILES(
      CASE
        WHEN ts_started IS NOT NULL AND ts_submitted IS NOT NULL
        THEN SAFE_DIVIDE(ts_submitted - ts_started, 60000000)
      END,
      100
    )[OFFSET(90)], 1) AS p90_minutes,

    ROUND(SAFE_DIVIDE(COUNTIF(did_submit = 1 AND did_upload = 1), COUNTIF(did_submit = 1)) * 100, 1) AS pct_submitted_with_docs
  FROM eligible
  GROUP BY platform, claim_type
),

flagged AS (
  SELECT
    *,
    CASE
      WHEN overall_cvr < 55.0 THEN 'P0 — overall conversion below 55% (baseline 64%)'
      WHEN cvr_s2_to_s3 < 72.0 THEN 'P1 — step 2→3 drop-off below 72% (baseline 82%)'
      WHEN cvr_s3_to_s4 < 74.0 THEN 'P1 — step 3→4 drop-off below 74% (baseline 84%)'
      WHEN cvr_upload_to_submit < 85.0 THEN 'P1 — upload→submit drop below 85% (baseline 93%)'
      WHEN p90_minutes > 45.0 THEN 'P2 — p90 time-to-submit above 45 min (baseline 28 min)'
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
  CASE
    WHEN alert_flag LIKE 'P0%' THEN 1
    WHEN alert_flag LIKE 'P1%' THEN 2
    WHEN alert_flag LIKE 'P2%' THEN 3
    ELSE 4
  END,
  platform,
  claim_type;
