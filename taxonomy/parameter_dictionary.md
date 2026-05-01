# Parameter Dictionary

**Version:** 2.1  
**Owner:** Data Analytics  
**Applies to:** All custom Firebase Analytics events  
**Last updated:** 2025-10-01

---

## Universal Parameters

These parameters must be present on every custom event unless marked optional.

| Parameter | Type | Required | Description | Example |
|---|---|---|---|---|
| `user_id` | string | Yes* | Internal user identifier. Set via `setUserId()` post-authentication. Null only for pre-auth events. | `"usr_8f3a2c"` |
| `session_id` | string | Yes | Firebase-assigned session identifier | `"1718392847_abc"` |
| `platform` | string | Yes | `"ios"` or `"android"` — lowercase | `"android"` |
| `app_version` | string | Yes | Semantic version of the app | `"4.13.2"` |
| `environment` | string | Yes | `"production"`, `"staging"`, or `"debug"` | `"production"` |

*`user_id` is omitted for events that fire pre-authentication (e.g., `signup_started`, `login_started`).

---

## Domain-Specific Parameters

### Authentication

| Parameter | Type | Events | Description |
|---|---|---|---|
| `auth_method` | string | `login_success`, `signup_completed` | `"email"`, `"google"`, `"apple"`, `"sms"` |
| `failure_reason` | string | `login_failed` | `"invalid_credentials"`, `"account_locked"`, `"network_error"` |

---

### Onboarding

| Parameter | Type | Events | Description |
|---|---|---|---|
| `step_index` | integer | `onboarding_step_completed` | 1-indexed step number (1–6) |
| `step_name` | string | `onboarding_step_completed` | Human-readable step identifier: `"profile_setup"`, `"id_verification"`, `"payment_method"`, `"preferences"`, `"notifications"`, `"confirmation"` |
| `is_returning_user` | string | `onboarding_started` | `"true"` or `"false"` — returning users who re-enter onboarding after account reset |

---

### Claim Flow

| Parameter | Type | Events | Description |
|---|---|---|---|
| `claim_id` | string | All `claim_*` events | Server-assigned claim identifier. Must be set after API response, not before. | 
| `claim_type` | string | `claim_started`, `claim_submitted` | `"property"`, `"vehicle"`, `"health"`, `"travel"` |
| `step_index` | integer | `claim_step_completed` | 1-indexed (1–4) |
| `step_name` | string | `claim_step_completed` | `"incident_details"`, `"evidence_upload"`, `"review"`, `"confirmation"` |
| `has_documents` | string | `claim_submitted` | `"true"` or `"false"` |
| `rejection_reason` | string | `claim_rejected` | `"incomplete_documents"`, `"out_of_coverage"`, `"duplicate"`, `"expired_policy"` |

---

### Payments

| Parameter | Type | Events | Description |
|---|---|---|---|
| `transaction_id` | string | `payment_completed`, `payment_refunded` | Payment provider transaction ID. Must be captured from API response, never generated client-side. |
| `amount` | float | `payment_completed`, `payment_refunded` | Amount in major currency units (EUR, not cents). `49.99` not `4999`. |
| `currency` | string | `payment_completed` | ISO 4217 code. `"EUR"` |
| `payment_method` | string | `payment_completed`, `payment_method_selected` | `"card"`, `"sepa_debit"`, `"apple_pay"`, `"google_pay"` |
| `error_code` | string | `payment_failed` | Payment provider error code: `"card_declined"`, `"insufficient_funds"`, `"expired_card"`, `"processing_error"` |
| `is_retry` | string | `purchase_initiated` | `"true"` if this is a retry after a failed attempt |

---

### Documents

| Parameter | Type | Events | Description |
|---|---|---|---|
| `document_type` | string | `document_uploaded`, `document_upload_failed` | `"id_card"`, `"proof_of_address"`, `"invoice"`, `"photo"`, `"other"` |
| `file_size_kb` | integer | `document_uploaded` | File size in kilobytes |
| `upload_duration_ms` | integer | `document_uploaded` | Time from upload initiation to server confirmation, in milliseconds |

---

### Notifications & Messaging

| Parameter | Type | Events | Description |
|---|---|---|---|
| `campaign_id` | string | `notification_opened`, `in_app_message_clicked` | CRM campaign identifier from Commanders Act |
| `notification_type` | string | `notification_opened` | `"push"`, `"in_app"`, `"email"` (for cross-channel tracking) |
| `deeplink_target` | string | `notification_opened` | Screen or flow the notification routes to: `"claim_form"`, `"payment"`, `"home"` |

---

### Errors

| Parameter | Type | Events | Description |
|---|---|---|---|
| `error_type` | string | `error_occurred` | Must use approved enum: `"auth_error"`, `"network_timeout"`, `"validation_failed"`, `"server_error"`, `"permission_denied"`, `"session_expired"`, `"file_too_large"`, `"unsupported_format"`, `"payment_declined"`, `"unknown"` |
| `error_code` | string | `error_occurred` | Internal or provider error code. Optional. |
| `screen_name` | string | `error_occurred` | Screen where the error occurred |

---

### Filters & Search

| Parameter | Type | Events | Description |
|---|---|---|---|
| `filter_count` | integer | `filter_applied` | Number of active filters after apply |
| `filter_types` | string | `filter_applied` | Comma-separated list of filter categories applied: `"date,type,status"` |
| `query_length` | integer | `search_performed` | Character count of the search query (do not capture query text — PII risk) |
| `results_count` | integer | `search_performed` | Number of results returned |

---

### Consent

| Parameter | Type | Events | Description |
|---|---|---|---|
| `consent_analytics` | string | All consent events | `"granted"` or `"denied"` |
| `consent_marketing` | string | All consent events | `"granted"` or `"denied"` |
| `consent_personalization` | string | All consent events | `"granted"` or `"denied"` |
| `consent_source` | string | All consent events | `"first_launch"`, `"settings"`, `"update_prompt"` |

---

## Deprecated Parameters

| Parameter | Replaced by | Removal target |
|---|---|---|
| `uid` | `user_id` | v5.0 |
| `txn` | `transaction_id` | v5.0 |
| `step` | `step_index` | v5.0 |
| `notif_id` | `campaign_id` | v5.0 |
