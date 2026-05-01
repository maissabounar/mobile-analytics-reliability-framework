-- anomaly_detection_rolling.sql
-- Detects abnormal Firebase event volume by event_name and platform.
-- Uses a 7-day rolling baseline with z-score alerting.
-- Results feed Looker Studio and Slack alerting.
-- Replace `project.analytics_XXXXXXX` with your Firebase export project and dataset.
-- Depending on schema, replace `platform` with `device.operating_system` if needed.

WITH daily_counts AS (
  SELECT
    DATE(TIMESTAMP_MICROS(event_timestamp)) AS event_date,
    platform,
    event_name,
    COUNT(*) AS daily_count
  FROM `project.analytics_XXXXXXX.events_*`
  WHERE _TABLE_SUFFIX BETWEEN FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 37 DAY))
                          AND FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY))
    AND event_name NOT IN (
      'user_engagement',
      'screen_view',
      'session_start',
      'app_open',
      'os_update',
      'app_update'
    )
  GROUP BY event_date, platform, event_name
),

rolling_stats AS (
  SELECT
    event_date,
    platform,
    event_name,
    daily_count,

    AVG(daily_count) OVER (
      PARTITION BY platform, event_name
      ORDER BY event_date
      ROWS BETWEEN 7 PRECEDING AND 1 PRECEDING
    ) AS rolling_avg_7d,

    STDDEV_POP(daily_count) OVER (
      PARTITION BY platform, event_name
      ORDER BY event_date
      ROWS BETWEEN 7 PRECEDING AND 1 PRECEDING
    ) AS rolling_stddev_7d,

    LAG(daily_count) OVER (
      PARTITION BY platform, event_name
      ORDER BY event_date
    ) AS prev_day_count
  FROM daily_counts
),

anomaly_flags AS (
  SELECT
    event_date,
    platform,
    event_name,

    CASE
      WHEN event_name IN (
        'payment_completed',
        'claim_submitted',
        'login_success',
        'signup_completed',
        'consent_granted'
      ) THEN 'P0'
      WHEN event_name IN (
        'purchase_initiated',
        'payment_failed',
        'onboarding_step_completed',
        'claim_started',
        'document_uploaded'
      ) THEN 'P1'
      ELSE 'P2'
    END AS event_priority,

    daily_count,
    ROUND(rolling_avg_7d, 1) AS rolling_avg_7d,
    ROUND(rolling_stddev_7d, 1) AS rolling_stddev_7d,
    prev_day_count,

    ROUND(
      SAFE_DIVIDE(daily_count - rolling_avg_7d, NULLIF(rolling_stddev_7d, 0)),
      2
    ) AS z_score,

    ROUND(
      SAFE_DIVIDE(daily_count - prev_day_count, NULLIF(prev_day_count, 0)) * 100,
      1
    ) AS dod_change_pct,

    CASE
      WHEN ABS(SAFE_DIVIDE(daily_count - rolling_avg_7d, NULLIF(rolling_stddev_7d, 0))) > 3 THEN 'CRITICAL'
      WHEN ABS(SAFE_DIVIDE(daily_count - rolling_avg_7d, NULLIF(rolling_stddev_7d, 0))) > 2 THEN 'WARNING'
      ELSE 'OK'
    END AS alert_status,

    CASE
      WHEN daily_count < rolling_avg_7d THEN 'DROP'
      WHEN daily_count > rolling_avg_7d THEN 'SPIKE'
      ELSE 'STABLE'
    END AS direction
  FROM rolling_stats
  WHERE event_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY)
    AND rolling_avg_7d IS NOT NULL
    AND rolling_stddev_7d IS NOT NULL
    AND rolling_avg_7d >= 100
)

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
  alert_status,
  direction,
  CONCAT(
    '[', alert_status, '] ',
    event_name, ' on ', platform, ' — ',
    CAST(daily_count AS STRING), ' events vs ',
    CAST(rolling_avg_7d AS STRING), ' expected',
    ' (z=', CAST(z_score AS STRING), ', ',
    direction, ', ',
    IFNULL(CAST(ABS(dod_change_pct) AS STRING), '?'), '% DoD)'
  ) AS alert_message
FROM anomaly_flags
WHERE alert_status IN ('WARNING', 'CRITICAL')
ORDER BY
  CASE event_priority WHEN 'P0' THEN 1 WHEN 'P1' THEN 2 ELSE 3 END,
  CASE alert_status WHEN 'CRITICAL' THEN 1 ELSE 2 END,
  ABS(z_score) DESC;
