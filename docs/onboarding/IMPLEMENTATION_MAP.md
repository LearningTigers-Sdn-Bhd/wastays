# Hotel onboarding implementation map (Phase 0)

Verified against the Rails application code and schema on 12 August 2026. This is a discovery artifact only; it does not define new behavior. The target behavior is in `FLOW_DECISIONS.md` and `DESIGN_DECISIONS.md`.

## Executive findings

- `Hotel#status` currently mixes hotel lifecycle and wizard position. The stored values are `registered`, `email_verified`, `profile_incomplete`, `rooms_incomplete`, `inventory_incomplete`, `pending_review`, `approved`, `live`, and `suspended` (`app/models/hotel.rb:188-198`). There is no database check constraint and no enum; only presence is validated (`app/models/hotel.rb:118`, `db/schema.rb:1533-1582`).
- `approved` and `live` are operationally equivalent in every eligibility/scheduled-operation query found. They differ only in presentation: Settings calls only `live` “Live”; `approved` falls through to “Building profile” (`app/presenters/hotel_portal/settings_presenter.rb:181-187`). Production approval writes `approved`, while `live` is written only by seed/data tasks (`app/services/admin/hotels/approve_service.rb:13-31`, `db/seeds/per_pax_hotel_seeder.rb:18`, `db/seeds/three_month_active_hotel_seeder.rb:32`, `lib/tasks/data_factory.rake:171`, `lib/tasks/generate_hotel_dataset.rake:32`).
- Admin creation currently provisions the owner immediately with a shared password and creates an **approved** hotel. It has neither Create-only/Create-and-onboard semantics nor owner activation (`app/forms/admin/hotels/create_form.rb:5-67`, `app/services/hotel_ops/create_hotel.rb:1-51`, `app/controllers/admin/hotels_controller.rb:23-38`).
- A subscription plan cannot be selected at creation. The controller loads plans, but the plan field is rendered only for persisted hotels; create parameters and `CreateForm` omit `plan_id` (`app/controllers/admin/hotels_controller.rb:5-7,63-86`, `app/views/admin/hotels/_form.html.erb:44-54`).
- Existing `OnboardingSession` records are training appointments/admin tracking, not owner page progress. Completing “onboarding” both creates a synthetic final session and changes the hotel to `approved` (`app/models/onboarding_session.rb:1-24`, `app/services/admin/complete_onboarding.rb:1-28`).
- Secure token invitations already exist for staff/corporate users, and a staff invitation can carry the seeded Hotel Owner role. There is no distinct owner activation/password-reset mechanism. The current hotel-creation path does not use invitations (`app/models/invitation.rb:1-72`, `app/models/staff_invitation.rb:1-42`, `app/controllers/public/staff_invitations_controller.rb:1-65`).

## 1. Hotel status inventory

### Reads

| Concern | Current semantics | References |
|---|---|---|
| Status vocabulary | Nine string values; five wizard-stage values precede review. | `app/models/hotel.rb:188-198` |
| Setup/wizard test | `onboarding?` includes `registered` through `inventory_incomplete`; it excludes `pending_review`. Completion predicates infer progress from status ordering. | `app/models/hotel.rb:444-477` |
| Review queue | Only exact `pending_review`, sorted by onboarding duration. | `app/models/hotel.rb:215-222`; `app/controllers/admin/hotels/onboarding_controller.rb:1-7`; `app/controllers/admin/dashboard_controller.rb:6-10` |
| Admin list/summary | Legacy five states are grouped as Setup; `approved` and `live` are grouped as Active. | `app/queries/hotels_query.rb:3-9`; `app/queries/hotels_summary_query.rb:3-18`; `app/presenters/admin/hotels/index_presenter.rb:8-25` |
| Portal shell/dashboard | Shell is visually locked for `onboarding?` or `pending_review`; only dashboard explicitly renders pending-review content. No global route enforcement exists for setup states. | `app/controllers/hotel_portal/base_controller.rb:38-44`; `app/controllers/hotel_portal/dashboard_controller.rb:3-15` |
| Operational/booking eligibility | `active?` means `approved` or `live`; public booking additionally excludes the `easy` plan. Booking search and API index query both statuses. | `app/models/hotel.rb:224-233`; `app/services/booking_engine/availability_service.rb:29-41`; `app/controllers/api/v1/hotels_controller.rb:1-6` |
| Scheduled operations | Night audit scheduler runs for both `approved` and `live`. | `app/jobs/night_audits/run_scheduled_job.rb:1-15` |
| Completion reporting | Onboarding completion date is exposed only for `approved`/`live`. | `app/models/hotel.rb:553-569` |
| Suspension/auth | Login/request authentication is actually blocked by **Account** status, not directly by Hotel status. | `app/controllers/application_controller.rb:54-62`; `app/controllers/public/sessions_controller.rb:10-17` |
| Miscellaneous status UI | Room-type helper special-cases `inventory_incomplete`; Settings labels only exact `live` as Live. | `app/helpers/hotel_portal/room_types_helper.rb:21`; `app/presenters/hotel_portal/settings_presenter.rb:181-187` |

### Writes and transitions

| Writer | Transition/result | Notes/reference |
|---|---|---|
| Admin create form/service | Form supplies `approved`; `reverse_merge(status: "registered")` therefore does not replace it. | `app/forms/admin/hotels/create_form.rb:46-62`; `app/services/hotel_ops/create_hotel.rb:13-25` |
| Legacy owner wizard | `registered -> profile_incomplete -> rooms_incomplete -> inventory_incomplete`. | `app/models/hotel.rb:464-474`; callers: `app/forms/hotel_portal/profile_form.rb:20-29`, `app/controllers/hotel_portal/property_policies_controller.rb:8-18`, `app/services/hotel_portal/room_types/save_room_type.rb:14-29` |
| Submit | Any status may become `pending_review` if the current readiness predicate passes; predicate checks address/featured photo, room type/quantity, and any positive rate in the next 30 days. | `app/models/hotel.rb:476-500`; `app/controllers/hotel_portal/dashboard_controller.rb:42-51` |
| Admin training completion | Any legacy onboarding state or `pending_review` becomes `approved`; also upserts a final completed session. | `app/services/admin/complete_onboarding.rb:10-23` |
| Admin approve/reactivate | Normal approval writes `approved`; reactivation restores `pre_suspension_status` when present, otherwise `approved`. Account is activated in the same transaction. | `app/services/admin/hotels/approve_service.rb:10-35` |
| Admin suspend | Saves hotel and account prior statuses, then writes both to `suspended`. | `app/services/admin/hotels/suspend_service.rb:10-25`; columns at `db/schema.rb:1562,1569` |
| Fixtures/tasks | Seeds use `approved`, `pending_review`, and `live`; dataset tasks explicitly write `live`. These must be included in cleanup. | `db/seeds.rb:200-251`; `db/seeds/per_pax_hotel_seeder.rb:18`; `db/seeds/three_month_active_hotel_seeder.rb:32`; `lib/tasks/data_factory.rake:171`; `lib/tasks/generate_hotel_dataset.rake:32` |

Important defect: `Hotel` defines `ready_for_review?` twice. The earlier status-only implementation (`status == "inventory_incomplete"`) is overridden by the later domain-data implementation (`app/models/hotel.rb:460-477`). Migration/readiness work must not assume the first method is active.

## 2. Lifecycle semantic differences

| Current concept | Actual behavior | Target implication |
|---|---|---|
| `registered` / `email_verified` / `profile_incomplete` / `rooms_incomplete` / `inventory_incomplete` | Encodes a small legacy wizard directly in Hotel status. `email_verified` has no production writer found. | Collapse to `setup`; reconstruct page progress separately rather than translating status into full 13-page completion. |
| `pending_review` | Admin queue membership and pending dashboard, but completion can be bypassed by general Admin Approve. | Keep as lifecycle state; require new readiness/admin-review transition rules. |
| `approved` | Fully active, publicly bookable (except Easy), API-visible, scheduled for night audit. This is the state normal creation and approval produce. | Map to `live`; it is already “live” operationally. |
| `live` | Same eligibility as `approved`; only clearer Settings label. No normal production transition writes it. | Canonical target active state. |
| `suspended` | Hotel status is saved/restored, but Account suspension is the effective authentication block. | Preserve; remap stored pre-suspension hotel state too. Decide whether target suspension always suspends the whole account for multi-hotel accounts. |

## 3. Admin creation and owner provisioning

### Current input and side effects

- Create fields: company/group name, owner name/email, hotel name, address, city, country, star rating, salesperson id, preferred channel manager, amenities, sell mode, and boat-information flag (`app/forms/admin/hotels/create_form.rb:7-11`; `app/controllers/admin/hotels_controller.rb:69-86`). The UI also collects property/profile fields that the target delegates to the owner (`app/views/admin/hotels/_form.html.erb:18-100`).
- `Hotel` requires name, city, country, and sell mode, and makes sell mode immutable after create (`app/models/hotel.rb:105-130`). A target setup hotel cannot omit city/country without a validation strategy.
- The service transaction creates an active hotel Account, seeds four roles, creates an admin-role User with password `12345678`, gives that user Hotel Owner account role and hotel access, creates the Hotel, default GL maps/transaction codes, and a business-date record (`app/services/hotel_ops/create_hotel.rb:1-51`; role presets in `app/services/hotel_ops/seed_account_roles.rb:1-37`).
- There is one Create action and Cancel; success exposes the shared default password in flash/UI (`app/views/admin/hotels/_form.html.erb:207-244`; `app/controllers/admin/hotels_controller.rb:29-38`).
- Preferred provider is one nullable `hotels.preferred_channel_manager` string; there is no separate undecided decision field (`db/schema.rb:1563`).
- Salesperson ownership exists as optional `hotels.salesperson_id` (`app/models/hotel.rb:39-41`, `db/schema.rb:1564`).

### Plan support and gating

- `Hotel belongs_to :plan, optional: true`; plans and per-feature settings are `Plan`, `Feature`, and `PlanFeature` (`app/models/hotel.rb:41,236-260`; `app/models/plan.rb`; `app/models/feature.rb`; `app/models/plan_feature.rb`). With no plan, every `feature_enabled?` is false.
- Edit (not create) supports `plan_id` (`app/views/admin/hotels/_form.html.erb:44-54`; `app/controllers/admin/hotels_controller.rb:100`).
- Controller enforcement is `require_feature!`, with superadmin bypass (`app/controllers/concerns/plan_gated.rb:1-17`). Navigation/search also hide plan-gated entries (`app/helpers/hotel_portal/navigation_helper.rb:157-160`; `app/services/hotel_portal/global_search_service.rb:34,77`).
- Roles & Permissions is specifically gated by `role_based_access_control` and `manage_users` (`app/controllers/hotel_portal/roles_controller.rb:1-9`; `app/services/hotel_portal/global_search_service.rb:34`). Preset roles are nevertheless always seeded. Onboarding can safely show/confirm presets read-only, while post-launch custom role editing remains gated.
- Channel-manager admin onboarding is gated by `manage_40_otas` (`app/controllers/admin/hotels/channel_managers_controller.rb:1-13`). Public booking separately has hard-coded `plan.slug != "easy"`, not a PlanFeature (`app/models/hotel.rb:228-230`).

## 4. Reusable domain implementation map

Onboarding should orchestrate these existing records/APIs, not create parallel domain tables.

| Onboarding responsibility | Existing implementation to reuse / constraint |
|---|---|
| Property/profile/photos | `HotelPortal::ProfileForm`, `HotelPortal::PhotoQueue`, and profile photo actions (`app/forms/hotel_portal/profile_form.rb`; `app/services/hotel_portal/photo_queue.rb`; `app/controllers/hotel_portal/profiles_controller.rb`). Current legacy profile save advances Hotel status and must be decoupled. |
| Roles/permissions | `HotelOps::SeedAccountRoles` seeds Hotel Owner, General Manager, Front Desk, Housekeeper; `Role`, `Permission`, `RolePermission`, `UserHotelAccess`; custom UI in `HotelPortal::RolesController`. |
| Staff | Immediate `StaffInvitations::CreateService`/`ResendService`, `StaffInvitation#accept!`, and `StaffAccesses::{UpdateService,DestroyService}`. Existing create service sends immediately, so onboarding needs drafts/queueing rather than invoking it before submission (`app/services/staff_invitations/create_service.rb:24-41`). |
| Taxes/fees | `HotelPortal::TaxSettingsForm` for SST/tourism tax and `HotelPortal::HotelTaxesController` for custom tax rows (`app/controllers/hotel_portal/taxes_fees_controller.rb`; `app/controllers/hotel_portal/hotel_taxes_controller.rb`). |
| Room revenue | `TransactionCodes::Resolver`, `TransactionCodes::HotelTaxRuleChange`, `TransactionCodes::ApplyHotelTaxRuleChange`, `ReservationPolicies::EnsureDefaults`, and `HotelTransactionConfiguration` (`app/controllers/hotel_portal/room_revenue_controller.rb`). Do not initialize defaults merely by visiting a page. |
| Rooms/photos | `HotelPortal::RoomTypes::SaveRoomType`, `DestroyRoomType`, `DestroyPhotos`; RoomType records are saved directly (`app/controllers/hotel_portal/room_types_controller.rb`; `app/services/hotel_portal/room_types/`). Save currently advances legacy Hotel status for the first room. |
| Rate plans/per-pax | `RatePlans::EnsureSystemPlans`, `BootstrapAssignment`, `SaveRoomPricing`, `OccupancyLadder`, `Attach`, `RemoveRoomType`, plus `RoomTypeRatePlanOccupancyPrice` and `RatePlanAgeBand` (`app/services/rate_plans/`; `app/controllers/hotel_portal/rate_plans_controller.rb`; `app/controllers/hotel_portal/rate_plan_room_pricings_controller.rb`). Hotel sell mode uses stored value `per_person` although product wording says per pax (`app/models/hotel.rb:132-148`). |
| Rates/inventory | `HotelOps::BulkUpdateRates`, `BulkUpdateInventory`, `BulkUpdateRatesAndInventory`, `ApplyInventoryDashboardSelection`, and `ApplyPricingRules` accept date ranges (`app/services/hotel_ops/`). Existing readiness checks only 30-day positive rates and does not verify one-year inventory (`app/models/hotel.rb:492-496`). |
| Extra charges | `Financials::EnsureDefaultExtraCharges` and `ExtraCharges::Save` (`app/controllers/hotel_portal/extra_charges_controller.rb`). Index currently initializes defaults as a visit side effect. |
| Discounts | `Discounts::EnsureDefaults` and `Discounts::Save` (`app/controllers/hotel_portal/discounts_controller.rb`). Index currently initializes defaults as a visit side effect. |
| Payment methods | `PaymentMethods::EnsureDefaults` and `PaymentMethods::Save` (`app/controllers/hotel_portal/payment_methods_controller.rb`). Index currently initializes defaults as a visit side effect. |
| Corporate accounts | Relationship persistence in `HotelCorporateAccount`; invitations via `CorporateInvitations::{CreateService,ResendService,AcceptService}` (`app/controllers/hotel_portal/corporate_accounts_controller.rb`; `app/services/corporate_invitations/`). Existing create sends immediately and therefore also needs draft/queue orchestration. |
| Channel manager | `Admin::Hotels::OnboardChannexService`, `ChannelManagers::OnboardingService`, mapping diagnostics/repair, `SyncOrchestrator`, `SyncRatePlanAri`, and `FullRefreshService` (`app/services/channel_managers/`; `app/services/admin/hotels/onboard_channex_service.rb`). Channex full refresh is a 500-day horizon, longer than target initial one year (`app/services/channel_managers/full_refresh_service.rb:14-29`; `app/services/channel_managers/channex_adapter.rb:67`). |

## 5. Existing onboarding sessions/training

- `onboarding_sessions` store hotel, trainer, scheduled/completed times, meeting link, notes, and one of scheduled/completed/cancelled (`db/schema.rb:1872-1883`; `app/models/onboarding_session.rb`).
- Admin CRUD explicitly describes these as training sessions and stamps `notes = "TRAINING_SESSION"` (`app/controllers/admin/hotels/onboarding_sessions_controller.rb:1-145`).
- The tracker lists only `pending_review` hotels, permits arbitrary onboarding start/end dates, and uses a `FINAL_ONBOARDING_COMPLETION` session to calculate duration (`app/controllers/admin/hotels/onboarding_controller.rb`; `app/views/admin/hotels/_onboarding_tracker_table.html.erb`).
- `Admin::CompleteOnboarding` conflates training completion and hotel approval (`app/services/admin/complete_onboarding.rb`). No readiness check is run there.

**Recommended separation:** retain sessions as independent training/history records and stop using them as page progress or lifecycle authority. Whether completed training is a launch blocker, warning, or unrelated operation remains an explicit product decision.

## 6. Invitation and activation mechanisms

### Available

- Invitations use a SHA-256 digest of a 32-byte URL-safe random token, seven-day expiry, rotation on resend, accepted timestamp, and pending/expired scopes (`app/models/invitation.rb`).
- Staff acceptance creates or reactivates `UserHotelAccess` with the invitation role; a new user sets name/password/password confirmation through the token page (`app/models/staff_invitation.rb:20-30`; `app/controllers/public/staff_invitations_controller.rb:31-59`).
- Corporate invitations have their own create/accept flow and send immediately (`app/services/corporate_invitations/`; `app/controllers/public/corporate_invitations_controller.rb`).

### Gaps for owner onboarding

- No user activation fields, owner invitation subtype, or staff password-reset flow exists. Guest magic links are unrelated.
- Hotel creation creates a usable User immediately and relies on a shared default password (`app/services/hotel_ops/create_hotel.rb`; `app/views/admin/hotels/_form.html.erb:230-233`).
- Reusing `StaffInvitation` for an owner is structurally possible because it references any account Role, but owner semantics must be made explicit: account-level `UserRole` assignment, existing-user/account collision policy, intended `User#role`, invitation sender, post-accept resume route, and create-only behavior all require design/coverage.
- Existing staff acceptance always creates a new user with coarse role `hotel_staff`, while current owner creation uses coarse role `admin` plus account-level Hotel Owner role. Blind reuse would change authorization semantics (`app/controllers/public/staff_invitations_controller.rb:37-43`; `app/services/hotel_ops/create_hotel.rb:16-24`).

## 7. Migration matrix

This is the safe default mapping for data design; rows marked **decision required** must not be auto-migrated solely from status.

| Current hotel status | Target lifecycle | Initial section-progress evidence | Treatment / risk |
|---|---|---|---|
| `registered` | `setup` | No section may be inferred complete. | Resume at Property. Current admin-created approved hotels will not normally be here. |
| `email_verified` | `setup` | Do not encode verification in Hotel status; user/invitation evidence must be migrated separately. | No production writer was found; inspect actual row count/history before migration. |
| `profile_incomplete` | `setup` | Legacy profile action occurred, but target Property contract is broader; calculate from records and mark incomplete/needs attention if insufficient. | Do not automatically mark Property complete from status alone. |
| `rooms_incomplete` | `setup` | Profile and legacy property-policy actions occurred. | Revalidate target Property, roles, staff decision, taxes, and room revenue independently. |
| `inventory_incomplete` | `setup` | At least one room action occurred. | Revalidate rooms; no evidence of target rate/availability coverage or other phases. |
| `pending_review` | `pending_review` **or `setup` — decision required** | Snapshot/recompute all 13 completion contracts. | Existing submission only proves old profile/room/30-day-rate readiness. If target readiness fails, either grandfather pending review with warnings or return to setup/needs attention. |
| `approved` | `live` | Historical onboarding summary may be absent. | Operational semantics already equal live; preserve access/bookability. Convert `pre_suspension_status == approved` to `live`. |
| `live` | `live` | Preserve as-is. | Canonical active state. |
| `suspended` | `suspended` | Preserve records; remap `pre_suspension_status` using this matrix. | Account suspension coupling and multi-hotel behavior need confirmation. |
| Unknown/null | quarantine; no automatic mapping | None. | Status is presence-validated but unconstrained; audit distinct production values before migration. |

Migration must update all compatibility readers/writers listed above, plus factories, seeds/data tasks, API/public booking scopes, night-audit scheduling, admin summaries, Settings labels, and `pre_suspension_status`. Add a database constraint/validated lifecycle API only after compatibility deployment.

## 8. Unresolved decisions / required data checks

1. How actual existing non-live hotels split between `setup` and `pending_review`; run production counts by status plus readiness evidence before writing migration rules.
2. Whether old `pending_review` submissions are grandfathered, returned to setup, or revalidated under all target launch checks.
3. Whether training sessions are a launch prerequisite, a warning, or independent; retain history regardless.
4. Whether suspension remains account-wide. This matters if an Account can ever own multiple hotels.
5. Exact owner activation model: dedicated owner invitation versus generalized staff invitation; coarse `User#role`, account-level role, existing-user collisions, invitation sender/expiry, and Create-only resend/start action.
6. Whether company/group Account details extend beyond current `name`, and what “internal ownership information” is required beyond `salesperson_id`.
7. Preferred channel manager representation: nullable string versus explicit undecided/provider/connection decision records; future mandatory status remains unresolved.
8. One-year local coverage policy: one-time population or maintained rolling horizon. Channex currently synchronizes 500 days, so define coverage calculation and extension behavior independently from external sync.
9. Whether the Easy plan should remain non-publicly-bookable and how this hard-coded rule relates to target launch/readiness.
10. Whether live hotels retain a read-only onboarding summary or only section/audit history.
11. ~~Corporate invitation queue representation and submission idempotency remain unresolved.~~ **Resolved in Phase 8:** corporate invitations queue in `onboarding_corporate_drafts`, whose `invitation_id` (unique where not null) plus `delivered_at` are the idempotent delivery marker — Phase 10 delivers the `undelivered` scope and stamps both in the same transaction. See `handoffs/PHASE_08_COMMERCIAL.md`. **Staff drafts resolved too:** `onboarding_staff_drafts` now carries the same `invitation_id` + `delivered_at` marker and `undelivered` scope, and `Onboarding::DeliverInvitations` delivers both draft kinds resumably. Phase 10 only has to call it.
12. Target `setup` validation strategy for city/country and other owner-owned profile fields currently required at Hotel creation.
