# Mobile Analytics Reliability Framework

**Role:** Digital Data Analyst  
**Scope:** Tracking audit, event taxonomy, QA, BigQuery validation, consent monitoring

![Status](https://img.shields.io/badge/status-portfolio--project-0d1117)
![Scope](https://img.shields.io/badge/scope-mobile%20analytics-blue)
![Stack](https://img.shields.io/badge/stack-Firebase%20%7C%20BigQuery%20%7C%20Commanders%20Act-orange)
![Focus](https://img.shields.io/badge/focus-data%20quality%20%26%20tracking-success)
![Privacy](https://img.shields.io/badge/privacy-consent%20monitoring-critical)

A mobile analytics reliability project focused on improving tracking quality across iOS and Android.

The project audits Firebase-style mobile events, standardizes the tracking taxonomy, validates critical business events in BigQuery, and adds consent monitoring for analytics collection.

---

## TL;DR

- Reduced payment reconciliation gap from **34% to 1.2%**
- Reduced Android `transaction_id` null rate from **12.4% to 0.0%**
- Reduced Android `claim_submitted` duplication from **7.9% to 0.2%**
- Improved P0/P1 cross-platform event parity from **63% to 96%**
- Added daily validation checks for nulls, duplicates, naming, parity, and event sequence issues
- Added privacy checks to monitor pre-consent event collection

---

## How to Read This Repo

| Time | Start here |
|---|---|
| 2 minutes | `impact/results.md` |
| Technical review | `sql/validation_suite.sql` and `sql/funnel_claim_submission.sql` |
| Tracking review | `tracking_implementation/commanders_act_tracking.js` |
| QA review | `tracking_implementation/qa_debugging.md` |
| Governance review | `taxonomy/parameter_dictionary.md` and `data_quality_framework/validation_rules.md` |
| Privacy review | `privacy_consent/gdpr_compliance.md` |

---

## The Problem

A mobile app running Firebase Analytics and BigQuery had several tracking reliability issues.

The dashboard looked stable, but the underlying event data had gaps.

Main issues found:

- Duplicate `claim_submitted` events on Android
- Missing `transaction_id` values on Android payments
- Missing funnel events on Android
- Inconsistent event names between iOS and Android
- Deprecated events still appearing in production
- Custom events firing before consent status was known

These issues affected reporting, CRM activation, funnel analysis, and privacy monitoring.

---

## What Was Built

### 1. Event Audit

Created an event audit log covering:

- Event name
- Platform
- Severity
- Issue type
- Root cause
- Fix version

### 2. Tracking Taxonomy

Built a standardized taxonomy with:

- Approved event list
- Parameter dictionary
- Required fields
- Enum values
- Deprecated event mapping
- Cross-platform naming rules

### 3. Measurement Plan

Documented P0 event definitions for critical events such as:

- `claim_submitted`
- `payment_completed`

Each definition includes:

- Trigger logic
- Required parameters
- Platform implementation notes
- QA rules
- BigQuery validation notes

### 4. Tracking Implementation

Reworked client-side tracking logic with:

- Consent gating
- Required parameter validation
- Server-confirmed triggers
- Duplicate prevention
- Consistent payload structure

### 5. BigQuery Validation Suite

Built daily checks for:

- Null business IDs
- Duplicate conversions
- Naming compliance
- iOS and Android parity
- Event sequence integrity
- Debug events in production

### 6. Privacy Monitoring

Added consent checks to verify that:

- Analytics storage starts denied by default
- Custom events do not fire before consent
- Consent events are available in BigQuery
- Consent source is populated

---

## Results

![Data Quality — Before vs After](assets/data_quality_before_after.png)

| Area | Before | After |
|---|---:|---:|
| Payment reconciliation gap | **34%** | **1.2%** |
| Monthly revenue gap in analytics | **€41 200** | **€1 480** |
| `transaction_id` null rate on Android payments | **12.4%** | **0.0%** |
| `claim_submitted` duplication rate on Android | **7.9%** | **0.2%** |
| `user_id` null rate on post-auth P0 events | **8.3%** | **0.1%** |
| Cross-platform event parity for P0/P1 events | **63%** | **96%** |
| Event types firing before consent | **4** | **0** |
| Data engineering time spent on investigations | **~40% of week** | **~8% of week** |
| P0 issue resolution time | **3–5 days** | **< 4 hours** |
| Sales reporting escalations linked to data gaps | **3 in Q3** | **0 in Q4** |

> [!NOTE]
> The Android claim conversion rate moved from 71% to 64% after duplicate events were removed. This was a measurement correction, not a product regression.

---

## Stack

| Area | Tools |
|---|---|
| Tracking | Firebase Analytics, Commanders Act |
| Data | BigQuery, dbt |
| QA | Firebase DebugView, Analytics Debugger for Apps |
| Monitoring | BigQuery Scheduled Queries |
| Platforms | iOS, Android |
| Languages | SQL, JavaScript, YAML |

---

## Repository Structure

```text
audit/
  event_audit_log.csv

taxonomy/
  approved_event_list.csv
  parameter_dictionary.md

measurement_plan/event_definitions/
  claim_submitted.yaml
  payment_completed.yaml

tracking_implementation/
  commanders_act_tracking.js
  qa_debugging.md

sql/
  funnel_claim_submission.sql
  anomaly_detection_rolling.sql
  validation_suite.sql

data_quality_framework/
  validation_rules.md

privacy_consent/
  gdpr_compliance.md

impact/
  results.md

assets/
  data_quality_before_after.png
```
---

## Key Files

| File | Purpose |
|---|---|
| `impact/results.md` | Before/after results and business impact |
| `taxonomy/approved_event_list.csv` | Approved event taxonomy |
| `taxonomy/parameter_dictionary.md` | Parameter rules, types, and enum values |
| `measurement_plan/event_definitions/claim_submitted.yaml` | P0 claim conversion event definition |
| `measurement_plan/event_definitions/payment_completed.yaml` | P0 payment event definition |
| `tracking_implementation/commanders_act_tracking.js` | Consent-gated event tracking logic |
| `tracking_implementation/qa_debugging.md` | QA process for real-time and post-release validation |
| `sql/validation_suite.sql` | Daily BigQuery data quality checks |
| `data_quality_framework/validation_rules.md` | Rule catalog with severity and thresholds |
| `privacy_consent/gdpr_compliance.md` | Consent implementation and validation logic |

---

## What This Project Demonstrates

- Mobile analytics tracking QA
- Firebase Analytics event governance
- BigQuery validation logic
- Funnel and conversion reliability
- Cross-platform event parity monitoring
- Consent-aware tracking design
- Data quality rules for business-critical events
- Clear documentation for Product, Engineering, CRM, and Analytics teams
