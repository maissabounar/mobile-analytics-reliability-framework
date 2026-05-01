# Mobile Analytics Reliability Framework

**Role:** Digital Data Analyst — owned end-to-end analytics reliability (tracking, data, monitoring)


![Status](https://img.shields.io/badge/status-production--grade-0d1117)
![Scope](https://img.shields.io/badge/scope-mobile%20analytics-blue)
![Stack](https://img.shields.io/badge/stack-Firebase%20%7C%20BigQuery%20%7C%20Commanders%20Act-orange)
![Focus](https://img.shields.io/badge/focus-data%20quality%20%26%20tracking-success)
![GDPR](https://img.shields.io/badge/gdpr-compliant-critical)


Product and Sales teams flagged a 34% gap between our analytics and Stripe. The DPO found we'd been tracking users before consent. Product had been optimizing a funnel built on duplicated events for 8 months.
Nobody knew. The data looked fine in the dashboard.

---

> [!IMPORTANT]
> **TL;DR**
> - Fixed broken mobile tracking (Firebase + BigQuery)
> - Reduced revenue gap from **34% → 1.2%**
> - Eliminated duplicates, null IDs, and GDPR issues
> - Built validation + monitoring system for long-term reliability

---

## How to Read This Repo

If you have **2 minutes**:
- Read this README
- Open `impact/results.md`

If you want the **technical depth**:
- Read `sql/funnel_claim_submission.sql`
- Read `sql/validation_suite.sql`

If you care about **tracking implementation**:
- Open `tracking_implementation/commanders_act_tracking.js`
- Open `tracking_implementation/qa_debugging.md`

If you care about **privacy and governance**:
- Open `privacy_consent/gdpr_compliance.md`
- Open `data_quality_framework/validation_rules.md`
---


## The Problem

A high-volume mobile app (iOS + Android) running Firebase Analytics + BigQuery had accumulated six compounding tracking failures:

- **Duplicate conversions** — `claim_submitted` duplicated at 7.9% on Android (UI trigger instead of API callback)
- **Missing revenue keys** — `transaction_id` null on 12.4% of Android payments
- **Broken funnels** — key events missing on Android (`purchase_initiated`, `document_uploaded`)
- **Platform divergence** — 9 events inconsistent across iOS/Android, breaking CRM attribution
- **GDPR violations** — events fired before consent; 340k+ pre-consent `first_open`
- **Naming chaos** — 17 non-compliant events (`notif_clicked` vs `notification_opened`)

Finance had flagged a persistent gap between analytics and Stripe but couldn't explain it. Product was making roadmap decisions on an inflated Android conversion baseline. The DPO had never reviewed the Firebase consent implementation.

---

## What Was Built

**1. Full audit** — Firebase DebugView sessions (iOS + Android), BigQuery event-level analysis, and production QA validation. Every issue logged with platform, severity, owner, and root cause.

**2. Standardized taxonomy** — Approved event list (38 events), parameter dictionary with enums and types, strict naming convention enforced in review and CI.

**3. Tracking implementation (Commanders Act)** — Rebuilt event dispatch logic with consent gating, parameter validation, and server-confirmed triggers. Eliminated duplicate fires, blocked partial payloads, and enforced consistent event structure across iOS and Android.

**4. Measurement plan** — YAML event definitions for all P0/P1 events with trigger logic, required parameters, platform-specific implementation, and QA rules.

**5. BigQuery validation suite** — Five production queries running daily: null rate monitoring, duplicate detection, naming compliance, platform parity, and event sequence integrity.

**6. Anomaly detection** — Rolling 7-day average + standard deviation per event and platform. Fires WARNING at z > 2, CRITICAL at z > 3.

**7. GDPR remediation** — Firebase initialized with deny-all defaults before SDK configuration. Commanders Act CMP callback wired to `setConsent()`. Consent audit trail in BigQuery.


---

## Results

![Data Quality — Before vs After](assets/data_quality_before_after.png)

| Area | Before | After |
|---|---|---|
| Revenue discrepancy (BigQuery vs Stripe) | **34%** | **1.2%** |
| Monthly revenue undercount | **€41,200** | **€1,480** |
| `transaction_id` null rate on `payment_completed` | **12.4%** | **0.0%** |
| `claim_submitted` duplication rate (Android) | **7.9%** | **0.2%** |
| `user_id` null rate on P0 post-auth events | **8.3%** | **0.1%** |
| Cross-platform event parity (P0/P1 events) | **63%** | **96%** |
| Pre-consent tracking violations | **4 event types** | **0** |
| Data engineer time on incident investigation | **~40% of week** | **~8% of week** |
| Analytics incident resolution time | **3–5 days** | **< 4 hours** |
| Finance escalations due to data discrepancy | **3 in Q3** | **0 in Q4** |

---

## Stack

**Tracking**
Firebase Analytics · Commanders Act (TMS + CMP, TCF 2.2)

**Data**
BigQuery (event-level, UNNEST, scheduled queries) · dbt

**QA & Monitoring**
Firebase DebugView · Analytics Debugger for Apps · BigQuery validation suite

**Platforms**
iOS (Swift) · Android (Kotlin)

---

## Repository

```
audit/event_audit_log.csv               26 issues catalogued — event, platform, severity, fix version
taxonomy/approved_event_list.csv        38 standardized events with trigger, owner, platform
taxonomy/parameter_dictionary.md        All parameters, types, enums, GDPR flags
measurement_plan/claim_submitted.yaml   P0 event spec — trigger logic, params, QA rules, code
measurement_plan/payment_completed.yaml P0 event spec — revenue-critical, Stripe reconciliation
tracking_implementation/commanders_act_tracking.js  Commanders Act event logic with consent gating
tracking_implementation/qa_debugging.md             Mobile QA process with Analytics Debugger for Apps
sql/funnel_claim_submission.sql         Claim funnel with deduplication, alert flags, time distribution
sql/anomaly_detection_rolling.sql       Rolling z-score anomaly detection across all P0/P1 events
sql/validation_suite.sql                5 daily checks — nulls, duplicates, naming, parity, sequence
data_quality_framework/validation_rules.md  Full rule catalog — thresholds, severity, failure history
privacy_consent/gdpr_compliance.md      Consent implementation + audit findings + BigQuery checks
impact/results.md                       Full before/after metrics across 6 dimensions

```
