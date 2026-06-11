# Plan Feature Gating — Implementation Status

**Last updated:** 2026-06-08

---

## System Status: COMPLETE ✅

All infrastructure built and working. Remaining gaps are features not yet built in WAStays — wire them when built using the pattern at the bottom of this doc.

### What's built
- `plans`, `feature_groups`, `features`, `plan_features` DB tables
- `hotels.plan_id` FK — each hotel points to one plan
- Gating API on `Hotel`: `feature_enabled?`, `feature_level`, `feature_addon?`
- `PlanGated` concern with `require_feature!` — included in `ApplicationController`
- `PlanFeaturesHelper#feature_enabled_for_hotel?` — for view/sidebar checks
- Seed: 5 plans (Easy/Direct/Core/Plus/Enterprise) × 56 features × 155 plan_features, mirrors pricing matrix. "Pro" → **Plus**.
- Admin matrix UI: `/admin/plans` — superadmin toggles checkmarks per plan. Level dropdowns hidden (data preserved, not used yet). Add-on = single checkbox.
- Hotel plan assignment: admin hotel edit form dropdown
- Admin sidebar: "Plans" link under Operations
- Hotel portal sidebar: 12 nav items auto-hide based on plan

---

## ✅ Fully Wired (Controller + Sidebar)

| Feature Slug | Controller | Sidebar Item |
|---|---|---|
| `daily_occupancy_revenue` | `reports#daily_occupancy` | Reports › Daily Occupancy |
| `arrivals_departures_list` | `reports#arrivals_departures` | Reports › Arrivals & Departures |
| `outstanding_balance_noshow` | `reports#outstanding_balance` | Reports › Outstanding Balance |
| `housekeeper_productivity` | `reports#managers_flash` | Reports › Manager Flash |
| `booking_source_analysis` | `reports#breakdown` | Reports › Financial Breakdown |
| `revenue_allocation_per_night` | `reports#daily_revenue` | Reports › Daily Revenue |
| `task_assignment_minibar_log` | `requests#index` | Requests |
| `room_status_board` | `room_status_board#index` | Room Status |
| `unified_guest_profile` | `guests` (whole) | Guest Records |
| `role_based_access_control` | `roles` (whole) | Roles & Permissions |
| `full_audit_trail` | `audit_logs` (whole) | Operation Logs |
| `no_show_auto_handling` | `night_audits` (whole) | Night Audit |
| `excel_pdf_export` | `reports` format block (CSV/XLS/PDF) | Export buttons hidden in all report views |
| `automated_prearrival` | `Notifications::Dispatcher` (service-layer) | n/a — background notification |
| `checkin_confirmation` | `Notifications::Dispatcher` (service-layer) | n/a — background notification |
| `welcoming_instay_messaging` | `Notifications::Dispatcher` (service-layer) | n/a — all plans enabled, gate ready |
| `checkout_receipt_review` | `Notifications::Dispatcher` (service-layer) | n/a — all plans enabled, gate ready |
| `ai_concierge_page` | `knowledge_*`, `knowledge_diagnostics`, sidebar, hotel global search, public concierge QR flow, hotel concierge QR page | Knowledge nav + concierge QR entry hidden; public concierge redirects to hotel page when excluded |

---

## ❌ Not Wired — Pending

### AIC — External flows (n8n / WhatsApp)
No Rails controller. Gate via n8n webhook auth or a settings toggle when ready.
`whatsapp_automation_flows`, `llm_hotels_resorts_homestays`, `guest_engagement_flow`, `ai_concierge_flow`, `activity_offers_flow`, `housekeeping_flow`, `complaint_system_flow`

### Booking Engine
| Slug | Next Action |
|---|---|
| `payment_system` | Gate in direct booking / payment settings controller |
| `billing_invoicing_system` | Gate in billing settings |
| `direct_booking_flow` | Gate in public booking controller |
| `folio_management_billing` | Gate folio / checkout surfaces once plan gating is wired there |

### Channel Manager
No hotel_portal CM controller exists yet. Build CM management page first, then gate.
`manage_40_otas`, `auto_sync_availability`

### PMS — Too broad / core operations
Gating these would break core booking flows. Revisit when PMS tiers are explicitly surfaced in UI.
`reservation_management`, `room_management_availability`, `front_desk_operations`

### Rate Management — No dedicated per-feature pages yet
`rate_plan_hierarchy`, `date_range_dow_pricing`, `rate_override_reason_code`, `min_max_stay_rules`, `last_minute_rate_automation`, `instant_rate_sync`

### Guest Profile — Field-level (not page-level)
Hide specific fields in guest show/edit views using `feature_enabled_for_hotel?`.
`preference_tagging`, `complaint_history`, `vip_blacklist_flag`, `whatsapp_linked_to_profile`

### Comms — Mostly wired (service-layer in `Notifications::Dispatcher`)
✅ Wired: `automated_prearrival`, `checkin_confirmation`, `welcoming_instay_messaging`, `checkout_receipt_review`
❌ `internal_staff_alerts` — no matching `notification_type` in `NotificationConfig::NOTIFICATION_TYPES`. Build the notification type first, then add to `Dispatcher::NOTIFICATION_FEATURE`.

### System — Not built yet
`offline_mode`, `multi_property_view`, `shift_handover_log`, `mobile_friendly_management` (responsive, not a page)

### Add-ons — Not built yet
`live_chat`, `e_invoice`, `accounting_integration`, `per_pax_booking`

### Other
| Slug | Note |
|---|---|
| `excel_pdf_export` | Format option on all reports — hide export buttons per report view |
| `backdated_checkin_rate` | No matching report action found yet |
| `priority_room_flagging` | No dedicated controller |
| `maintenance_request_tracking` | Covered by `task_assignment_minibar_log` (same requests controller) |

---

## How to Wire a New Feature

### 1. Controller (block URL access)
```ruby
# app/controllers/hotel_portal/your_controller.rb
before_action -> { require_feature!("your_slug") }
# or specific actions only:
before_action -> { require_feature!("your_slug") }, only: %i[index show]
```

### 2. Hotel portal sidebar (hide nav item)
Add `plan_feature: "your_slug"` to the item hash in `app/views/shared/navigation/_hotel_sidebar.html.erb`. The filter loop at line ~80 handles the rest automatically.

### 3. View field level (sub-features like guest profile fields)
```erb
<% if feature_enabled_for_hotel?("preference_tagging") %>
  <%= f.text_field :preference_tags %>
<% end %>
```

### 4. Level-based logic (future — when level UI is re-enabled)
```ruby
if current_hotel.feature_level("front_desk_operations") == "advanced"
  # show advanced UI
end
```
