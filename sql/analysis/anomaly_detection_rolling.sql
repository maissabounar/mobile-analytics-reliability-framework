-- Anomaly Detection: Rolling Average + Standard Deviation
-- Detects abnormal event volume by event_name and platform
-- using a 7-day rolling baseline with ±2σ alert thresholds
-- Runs daily via scheduled BigQuery job; results feed Looker Studio alert dashboard

WITH

-- Daily event counts per event_name + platform
daily_counts AS (
  SELECT
    DATE(TIMESTAMP_MICROS(event_timestamp)) AS event_date,
    platform,
    event_name,
    COUNT(*) AS daily_count
  FROM `project.analytics_XXXXXXX.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 37 DAY))
                      AND FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY))
  GROUP BY 1, 2, 3
),

-- Compute 7-day rolling stats (excluding current day to avoid partial-day bias)
rolling_stats AS (
  SELECT
    event_date,
    platform,
    event_name,
    daily_count,

    -- Rolling 7-day average over the 7 days preceding today
    AVG(daily_count) OVER (
      PARTITION BY platform, event_name
      ORDER BY event_date
      ROWS BETWEEN 7 PRECEDING AND 1 PRECEDING
    ) AS rolling_avg_7d,

    -- Rolling 7-day standard deviation
    STDDEV_POP(daily_count) OVER (
      PARTITION BY platform, event_name
      ORDER BY event_date
      ROWS BETWEEN 7 PRECEDING AND 1 PRECEDING
    ) AS rolling_stddev_7d,

    -- Day-over-day change
    LAG(daily_count, 1) OVER (
      PARTITION BY platform, event_name
      ORDER BY event_date
    ) AS prev_day_count

  FROM daily_counts
),

-- Compute z-score and classify anomalies
anomaly_flags AS (
  SELECT
    event_date,
    platform,
    event_name,
    daily_count,
    ROUND(rolling_avg_7d, 1)    AS rolling_avg_7d,
    ROUND(rolling_stddev_7d, 1) AS rolling_stddev_7d,
    prev_day_count,

    -- Z-score: how many standard deviations from the rolling mean
    ROUND(
      SAFE_DIVIDE(
        (daily_count - rolling_avg_7d),
        NULLIF(rolling_stddev_7d, 0)
      ),
      2
    ) AS z_score,

    -- Day-over-day pct change
    ROUND(
      SAFE_DIVIDE(
        (daily_count - prev_day_count),
        NULLIF(prev_day_count, 0)
      ) * 100,
      1
    ) AS dod_change_pct,

    -- Alert level: critical if |z| > 3, warning if |z| > 2
    CASE
      WHEN ABS(SAFE_DIVIDE((daily_count - rolling_avg_7d), NULLIF(rolling_stddev_7d, 0))) > 3 THEN 'CRITICAL'
      WHEN ABS(SAFE_DIVIDE((daily_count - rolling_avg_7d), NULLIF(rolling_stddev_7d, 0))) > 2 THEN 'WARNING'
      ELSE 'NORMAL'
    END AS alert_level,

    -- Direction: volume drop vs spike
    CASE
      WHEN daily_count < rolling_avg_7d THEN 'DROP'
      WHEN daily_count > rolling_avg_7d THEN 'SPIKE'
      ELSE 'STABLE'
    END AS direction,

    -- Event priority (join from hardcoded reference — or replace with a priority lookup table)
    CASE
      WHEN event_name IN ('payment_completed', 'claim_submitted', 'login_success', 'signup_completed', 'consent_granted')
        THEN 'P0'
      WHEN event_name IN ('purchase_initiated', 'payment_failed', 'onboarding_step_completed', 'claim_started', 'document_uploaded')
        THEN 'P1'
      ELSE 'P2'
    END AS event_priority

  FROM rolling_stats
  -- Only analyze the most recent 7 days (rolling window fully populated by then)
  WHERE event_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY)
  -- Require at least 5 days of history to produce meaningful stats
  AND rolling_avg_7d IS NOT NULL
  AND rolling_stddev_7d IS NOT NULL
)

-- Final output: anomalies sorted by priority and severity
SELECT
  event_date,
  platform,
  event_name,
  event_priority,
  daily_count,
  rolling_avg_7d,
  rolling_stddev_7d,
  z_score,
  dod_change_pct,
  alert_level,
  direction,
  -- Human-readable summary for Slack alert message
  CONCAT(
    '[', alert_level, '] ',
    UPPER(event_name), ' on ', platform, ' on ', CAST(event_date AS STRING), ': ',
    daily_count, ' events vs rolling avg ', rolling_avg_7d,
    ' (z=', z_score, ', ', direction, ' ', IFNULL(CAST(ABS(dod_change_pct) AS STRING), '?'), '%)'
  ) AS alert_message

FROM anomaly_flags
WHERE alert_level IN ('WARNING', 'CRITICAL')
ORDER BY
  CASE event_priority WHEN 'P0' THEN 1 WHEN 'P1' THEN 2 ELSE 3 END,
  CASE alert_level WHEN 'CRITICAL' THEN 1 ELSE 2 END,
  ABS(z_score) DESC
