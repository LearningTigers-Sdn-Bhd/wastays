# Single Booking Folio Readiness Matrix

Updated after Priority #1 Single Booking Folio Financial Safety Hardening.

| Area | Feature / Capability | Current Code Evidence | Status | Risk | Recommended Next Step |
|---|---|---|---|---|---|
| Data Model | Folio model | `BookingFolio`, table `booking_folios`, `Booking has_one :booking_folio`, `BookingFolio belongs_to :booking` | Ready | Low | Keep as single-booking folio aggregate root. |
| Data Model | One folio per booking | `db/schema.rb` unique index `index_booking_folios_on_booking_id`; `BookingFolio` validates hotel/booking match | Ready | Low | Keep uniqueness; add lifecycle service coverage around creation timing. |
| Data Model | Folio status lifecycle | `booking_folios.status` default `"open"`; `Folios::CloseForCheckout` sets `"closed"`; no enum or reopen state/rules | Partial | Medium | Add explicit status enum/state rules and controlled reopen service. |
| Data Model | Folio transactions | `FolioTransaction`, table `folio_transactions`, `BookingFolio has_many :folio_transactions` | Ready | Low | Continue routing all postings through `Folios::InsertTransaction`. |
| Data Model | Transaction codes | `FolioTransaction::CHARGE_CATEGORIES`, `PAYMENT_CATEGORIES`, `ADJUSTMENT_CATEGORIES`; `HotelGeneralLedgerMap` via `assign_gl_code` | Partial | Medium | Add first-class transaction code model/config if codes need operational control beyond category strings. |
| Data Model | Payments linked to folios | `Folios::RecordPaymentFromGateway`, `Folios::SyncExistingPayments`, metadata `payment_transaction_id`, unique index `index_folio_transactions_on_gateway_payment` | Partial | Medium | Add direct FK or reconciliation model if stronger payment-folio traceability is required. |
| Data Model | Refunds | `Folios::RecordRefund`, manual refund category in `PostStaffTransaction`, metadata `refund_request_id`, unique index `index_folio_transactions_on_refund_request` | Partial | Medium | Ensure all refund entry points call `RecordRefund` and verify gateway capture/sync before closing. |
| Data Model | Adjustments | `FolioTransaction` adjustment categories; `PostStaffTransaction` allows `adjustment`, `discount`, `correction`, `write_off`, `other` | Ready | Low | Keep reason requirements for sensitive categories. |
| Data Model | Void / reversal records | `reversal_of_transaction_id`, `voided_by_transaction_id`, `Folios::ReverseTransaction` | Ready | Low | Consider renaming UI language from void to reversal if void is only represented by reversing entries. |
| Data Model | Forecasted/upcoming charges | `FolioForecastedCharge`, `GenerateForecastedCharges`, `SyncForecastedCharges`, `actualizing_transaction_id` | Ready | Low | Keep forecasts separate from posted transactions. |
| Data Model | Business date on financial records | `FolioTransaction.posting_date`, `FinancialAuditEvent.business_date`, `HotelBusinessDate` guards | Ready | Low | Add direct `hotel_business_date_id` to folio transactions only if audit lineage needs stronger FK linkage. |
| Data Model | Night audit linkage on transactions | `folio_transactions.night_audit_id`, FK `on_delete: :restrict`, `PostNightlyCharges` sets `night_audit` and metadata | Ready | Low | Keep direct `night_audit_id` as source of audit-posting lineage. |
| Data Model | Audit logs for folio mutations | `FinancialAuditEvent`, `FinancialControls::AuditEventRecorder`, called by `InsertTransaction` and `CloseForCheckout` | Ready | Low | Add coverage for every non-posting folio status mutation, especially future reopen. |
| Data Model | Immutable posted transactions | `FolioTransaction#prevent_immutable_changes`, `#prevent_destroy`, specs in `folio_transaction_spec.rb` | Ready | Low | Keep allowing only `voided_by_transaction_id` mutation. |
| Data Model | Balance calculation/caching | `BookingFolio#outstanding_balance`, `#total_charges`, `#total_payments`, `#total_adjustments`; no cached balance column | Partial | Medium | Continue fresh DB sums for correctness or add carefully invalidated cached balances later. |
| Data Model | Currency and precision | `folio_transactions.amount decimal(10,2)`, `currency` now `null: false`; `FolioTransaction` validates `currency`; deposits `decimal(12,2)`; summaries `decimal(12/15,2)` | Ready | Low | Keep currency required for all folio postings; consider wider precision separately if needed. |
| Booking Lifecycle | Booking creation creates folio | `CreateManualBooking` saves booking and payment but does not call `Folios::InitializeForBooking`; online/public confirmation paths not clearly folio-initializing from inspected code | Partial | High | Decide whether folio is created at confirmation or check-in; enforce consistently. |
| Booking Lifecycle | Confirmation integration | `BookingEngine::ConfirmBooking` exists; folio creation not evidenced in inspected lifecycle grep | Unknown | Medium | Inspect/define confirmation as either folio-creating or intentionally deferred. |
| Booking Lifecycle | Walk-in check-in | `WalkInCheckInsController#create` creates manual booking then `TransitionStatus checked_in`; `TransitionStatus#check_in` initializes folio | Ready | Low | Add request/service spec for walk-in folio creation and payment sync. |
| Booking Lifecycle | Normal check-in | `CheckInsController#create` -> `Bookings::TransitionStatus#check_in` -> `Folios::InitializeForBooking` | Ready | Low | Keep check-in as safe folio initialization point. |
| Booking Lifecycle | Backdated check-in | `BackdatedCheckInsController`, `TransitionStatus#check_in`, `ProcessCatchUpCharges`; staff `posting_date` is no longer passed to catch-up; `retroactive_checkin_spec.rb` covers ignored/tampered posting date | Partial | Medium | Add more request-level coverage for review_no_show and no_show/reinstate edge cases. |
| Booking Lifecycle | review_no_show/no_show handling | `FinalizeNoShow` posts no-show charges; `ProcessCatchUpCharges#reverse_no_show_charges`; `ReinstateReservation` initializes folio and catch-up posts | Partial | Medium | Add tests for no-show charge reversal idempotency and folio consistency after reinstate. |
| Booking Lifecycle | Late checkout | `ProcessLateCheckout` posts `late_checkout_charge` through `PostCategoryCharge`; can transition `review_due_out` to `checkout_required` or `checked_in` | Partial | Medium | Add full checkout-after-late-checkout tests including balance and forecast sync. |
| Booking Lifecycle | Checkout | `TransitionStatus#check_out` calls `Folios::CloseForCheckout`; room dirty marking after status transition | Ready | Low | Keep checkout blocked by folio close result. |
| Booking Lifecycle | Cancellation | `TransitionStatus#cancel` changes booking and releases inventory; no folio close/void/refund behavior evidenced | Partial | Medium | Define folio behavior for cancellation: leave open, close zero-balance, or post cancellation/no-show charges. |
| Booking Lifecycle | Completion | Booking moves to `completed` only after `CloseForCheckout` succeeds | Ready | Low | Add integration spec from controller path through completed status. |
| Booking Lifecycle | Room release | Checkout marks rooms dirty; no-show/cancel release via `ReleaseAssignedRooms` and `InventoryManager` | Partial | Medium | Add folio-room consistency tests for backdated and no-show transitions. |
| Night Audit | Creates or updates folios | `NightAudits::Run` calls `ProcessNoShowReviews`, `ReviewDueOuts`, `PostNightlyCharges`; `PostNightlyCharges` skips missing folio instead of creating | Partial | High | Decide if audit should repair/create missing folios before posting or block pre-close. |
| Night Audit | Posts nightly room charges | `Folios::PostNightlyCharges` posts accommodation and tax for checked-in bookings on business date | Ready | Low | Keep service as audit-only posting entry point. |
| Night Audit | Creates missing charges | `PostNightlyCharges` posts for current audit date; `ProcessCatchUpCharges` handles closed-date missed charges for backdated/reinstate | Partial | Medium | Add explicit missing charge repair service for audit retries if needed. |
| Night Audit | Links transactions to night audit run | `PostNightlyCharges` passes `night_audit`, metadata `night_audit_id`; model validates direct/metadata match | Ready | Low | Keep both FK and metadata synchronized. |
| Night Audit | Duplicate posting prevention | Unique index on `metadata->>'nightly_charge_key'`; `PostNightlyCharges#posted_transaction`; catch-up now has `folio_transactions.catch_up_key` and unique partial index `index_folio_transactions_on_folio_and_catch_up_key` | Ready | Low | Keep idempotency keys DB-backed for any future automated posting paths. |
| Night Audit | Respects hotel business date | `NightAudits::Run#claim_business_date`, `PostingGuard`, `hotel.current_business_date`, `HotelBusinessDate` | Ready | Low | Keep financial postings tied to authoritative business date. |
| Night Audit | Financial summary values | `NightAudits::CalculateFinancialSummary` sums `FolioTransaction` by `posting_date` | Partial | Medium | Add specs comparing summary to posted folio transactions including reversals/refunds/write-offs. |
| Night Audit | Uses services not direct writes | `NightAudits::Run` -> `Folios::PostNightlyCharges` -> `InsertTransaction`; no direct transaction writes in night audit run path | Ready | Low | Keep direct writes out of audit code. |
| Financial Ops | Post room charge | Night audit accommodation via `PostNightlyCharges`; manual room charge category not allowed in `PostStaffTransaction` | Partial | Medium | Add controlled staff room-charge service or keep room charges audit-only by policy. |
| Financial Ops | Post manual charge | `PostStaffTransaction` allows charge category `other` only | Partial | Medium | Add transaction-code-driven manual charge categories if operationally needed. |
| Financial Ops | Post tax/service charge | Tax posted by `PostNightlyCharges`; manual tax rejected in request spec | Partial | Medium | Add explicit tax/service charge service if manual tax adjustments are required. |
| Financial Ops | Record payment | `PostStaffTransaction` cash; `RecordPaymentFromGateway`; checkout settlement payment in `CheckoutsController#post_checkout_settlement_payment` | Ready | Low | Keep permission split for staff payments. |
| Financial Ops | Refund payment | `RecordRefund` and manual refund category; amount sign enforced negative | Ready | Low | Add gateway-sync validation before checkout if refund is pending. |
| Financial Ops | Void transaction | No destructive void; represented as reversal via `ReverseTransaction` and `voided_by_transaction_id` | Partial | Medium | Decide whether void is operationally distinct from reverse. |
| Financial Ops | Reverse transaction | `ReverseTransaction` requires correction reason/note, locks original transaction, blocks double reversal | Ready | Low | Keep reversal as immutable correction path. |
| Financial Ops | Adjustment | `PostStaffTransaction` supports adjustments, discounts, corrections, write-offs | Ready | Low | Add tighter reason requirements for all sensitive adjustments, not only overrides/reversals. |
| Financial Ops | Write-off | `PostStaffTransaction` category `write_off`, permission `post_folio_write_offs` | Ready | Low | Add checkout/use-case specs around write-off settlement. |
| Financial Ops | Close folio | `CloseForCheckout` validates open folio, missing charges, zero balance, audit guard, sets invoice number | Ready | Low | Keep close exclusively service-driven. |
| Financial Ops | Reopen folio | No reopen service/action found | Missing | High | Add explicit reopen service with permissions, reason, audit event, and closed-date guard. |
| Financial Ops | Transfer transaction | No transfer action/service found | Missing | Medium | Defer; out of current single-folio scope unless operationally required. |
| Financial Ops | Deposit handling | `Deposit`, `Deposits::RecordSecurityDeposit`, `BookingFolio has_many :deposits`; not part of balance | Partial | Medium | Clarify whether security deposits affect folio balance or separate liability only. |
| Checkout | Validates folio exists | `CloseForCheckout` returns `"Booking has no folio."` | Ready | Low | Keep controller relying on service result. |
| Checkout | Validates folio open | `CloseForCheckout` rejects `"Folio is already closed."` | Ready | Low | Add controlled reopen only if required. |
| Checkout | Validates all charges posted | `CloseForCheckout#validate_all_nights_posted`, forecast sync before validation | Ready | Low | Add service-level tests for tax/accommodation forecast edge cases already partly present. |
| Checkout | Validates no missing nightly charges | Same as above; specs cover missing forecasts and under-posting | Ready | Low | Keep forecast actualization as required before close. |
| Checkout | Validates zero balance | `CloseForCheckout#calculate_fresh_balance`, rejects positive and negative balances | Ready | Low | Add policy for allowed settlement types if non-zero checkout is ever needed. |
| Checkout | Payment captured/synced | `Folios::CloseForCheckout#sync_payment_and_refund_state` syncs local captured `PaymentTransaction` records via `RecordPaymentFromGateway` before balance validation; covered in `close_for_checkout_spec.rb` | Ready | Low | Consider extracting shared sync predicates with `NightAudits::Evaluate` later. |
| Checkout | Refund captured/synced | `Folios::CloseForCheckout#sync_payment_and_refund_state` syncs completed `RefundRequest` via `RecordRefund` before balance validation; covered in `close_for_checkout_spec.rb` | Ready | Low | Keep checkout local-only; do not call external gateways during close. |
| Checkout | Audit log written | `FinancialAuditEvent` in `CloseForCheckout`; `BookingAuditLog` in `TransitionStatus#check_out` | Ready | Low | Keep both financial and booking audit trails. |
| Backdated Check-In | Creates/open folio | `BackdatedCheckInsController` -> `TransitionStatus#check_in` -> `InitializeForBooking` | Ready | Low | Keep initialization under booking lock. |
| Backdated Check-In | Posts missed room charges | `ProcessCatchUpCharges#post_missing_nightly_charges` for completed night audits; tests prove retry does not duplicate accommodation/tax catch-up charges | Ready | Low | Add broader lifecycle request specs around review_no_show/no_show. |
| Backdated Check-In | Uses business date correctly | Catch-up postings now use missed stay/audit `date`; `BackdatedCheckInsController` and `TransitionStatus` no longer pass staff `posting_date`; spec covers ignored selected date | Ready | Low | Keep staff-controlled accounting dates out of catch-up posting. |
| Backdated Check-In | Records override reason | Controller requires reason; `TransitionStatus` stores booking audit metadata; `ProcessCatchUpCharges` copies `backdate_reason` into transaction metadata/financial audit metadata | Ready | Low | Standardize reason taxonomy later if needed. |
| Backdated Check-In | Avoids duplicate charges | `ProcessCatchUpCharges#already_posted?` checks `catch_up_key` column first, then legacy metadata; DB unique partial index on `[booking_folio_id, catch_up_key]`; specs cover legacy metadata and DB uniqueness | Ready | Low | Keep metadata fallback until old rows are no longer relevant. |
| Backdated Check-In | Links to audit/business date | Catch-up uses `override_night_audit`; no direct `night_audit_id` for historical audit run | Partial | Medium | Link catch-up postings to relevant closed business date or audit where possible. |
| Backdated Check-In | Handles review_no_show safely | Allowed by `BackdatedCheckInsController`; `TransitionStatus` detects `was_review_no_show`; catch-up runs | Partial | Medium | Add request/service specs for review_no_show backdated check-in with folio assertions. |
| Backdated Check-In | Handles no_show safely | `ReinstateReservation` handles `no_show`, reverses no-show charges and catch-up posts | Partial | Medium | Add idempotency and room/folio consistency tests for reinstate. |
| Authorization | Policy/authorization | Controllers use permission checks: `manage_bookings`, `view_bookings`; posting permissions in `InsertTransaction` | Partial | Medium | Move folio operation authorization closer to services for all sensitive operations. |
| Authorization | Role checks | `current_user.has_permission?`; granular permissions for charges/payments/refunds/write-offs | Ready | Low | Keep granular permission names. |
| Authorization | Hotel scoping | Controllers fetch via `current_hotel.bookings.find`; `BookingFolio#hotel_matches_booking` | Ready | Low | Keep FK and validation. |
| Authorization | Operational guard during audit_running | `NightAudits::OperationalChangeGuard`, `FinancialControls::PostingGuard` block non-audit posting | Ready | Low | Ensure all new folio mutations call guards. |
| Authorization | Reason requirements | Reversals require reason/note; override postings require reason/note; cancellation and backdated check-in require reason | Partial | Medium | Require reasons for write-off, refund, manual adjustment, reopen, and closed-date posting uniformly. |
| Authorization | Staff-supplied bypass flags | Touched reversal/checkout/backdated paths no longer pass raw override params; `ReverseTransaction` derives closed-folio/closed-date override server-side; some unrelated check-in/reinstate flows still use explicit options | Partial | Medium | Continue replacing raw override params in remaining non-touched flows. |
| Architecture | Centralized posting | `Folios::InsertTransaction` is core path; services call it; grep found no direct controller `folio_transactions.create` | Ready | Low | Keep all financial posting in service layer. |
| Architecture | Service safety/idempotency | Locks in `InsertTransaction`, `InitializeForBooking`, `PostNightlyCharges`, `RecordPaymentFromGateway`, `RecordRefund`; catch-up has column-backed idempotency and metadata fallback | Ready | Low | Keep new automated posting flows behind explicit DB idempotency keys. |
| Architecture | Scattered lifecycle integration | Booking lifecycle services/controllers invoke folio services from several places: `TransitionStatus`, `ProcessEarlyDeparture`, `ProcessLateCheckout`, `FinalizeNoShow`, `ReinstateReservation` | Partial | Medium | Keep lifecycle orchestration in services; avoid adding folio behavior to views/controllers. |
| Database Safety | Indexes and FKs | FKs for folio, transactions, night audit, forecasts; indexes for posting date/category/reversal links; `catch_up_key` unique partial index added | Ready | Low | Keep future idempotency keys indexed at DB level. |
| Database Safety | Nullable vs required | `folio_transactions.description`, `folio_transactions.currency`, and `booking_folios.status` are now `null: false`; model validates `currency` | Ready | Low | Consider additional constraints only after data audit. |
| Database Safety | Idempotency keys | Unique indexes for nightly, no-show, early checkout, gateway payment, refund request, and catch-up key | Ready | Low | Keep metadata compatibility while using columns for new high-risk keys. |
| Database Safety | Locking/concurrency | `with_lock` on booking/folio in key services; DB unique indexes catch several duplicates | Partial | Medium | Add transaction boundaries and DB constraints for all high-risk posting flows. |
| Database Safety | Soft deletion/voiding | Transactions immutable and non-deletable; folios restrict transactions; forecasts can be destroyed/superseded | Partial | Medium | Prefer supersede/void strategy over destroys for financial-adjacent records. |
| Tests | Folio creation | Model specs and service behavior indirectly; limited direct lifecycle tests | Partial | Medium | Add specs for creation at check-in, walk-in, backdated, no-show/reinstate. |
| Tests | Posting charges | `post_nightly_charges_spec`, request folio transaction spec, late/early checkout specs | Ready | Low | Add manual room/tax behavior tests if added. |
| Tests | Payments/refunds | `record_payment_from_gateway_spec`, `sync_existing_payments_spec`, `record_refund_spec`, request manual payment/refund spec, checkout sync cases in `close_for_checkout_spec.rb` | Ready | Low | Add broader integration checkout sheet coverage later. |
| Tests | Adjustments/reversals | `folio_transactions_spec`, `folio_transaction_spec` cover adjustment/write-off/reversal basics | Partial | Medium | Add reason/authorization specs for all sensitive adjustment categories. |
| Tests | Checkout with balance | `close_for_checkout_spec` covers positive/negative/zero balance and missing charges | Ready | Low | Add controller/integration checkout sheet coverage. |
| Tests | Night audit posting | `post_nightly_charges_spec`, `night_audits_spec`, migration spec for `night_audit_id` | Ready | Low | Add financial summary/retry rollback tests. |
| Tests | Duplicate prevention | Nightly duplicate spec; catch-up retry, legacy metadata, and DB uniqueness specs added in `process_catch_up_charges_spec.rb` and migration specs | Ready | Low | Add true multi-thread concurrency spec later if needed. |
| Tests | Backdated check-in posting | `retroactive_checkin_spec.rb` covers missed-charge posting, ignored posting date, payment sync, and audit reason metadata | Partial | Medium | Add request-level backdated check-in specs. |
| Tests | Authorization | `folio_transactions_spec` covers granular permissions and touched override bypass attempts | Partial | Medium | Continue adding bypass tests as remaining flows are hardened. |
| Tests | Failure/rollback behavior | Some failure specs in `post_nightly_charges_spec`, `close_for_checkout_spec`; broader lifecycle rollback coverage limited | Partial | Medium | Add rollback specs for checkout, backdated check-in, reinstate, no-show posting failures. |

## Current Architecture Summary

The current implementation has a real single-booking folio foundation. `BookingFolio` is a one-to-one child of `Booking`, and `FolioTransaction` is the posted financial ledger. Forecasted charges are separated into `FolioForecastedCharge`, then actualized by posted transactions.

Financial posting is mostly centralized through `Folios::InsertTransaction`, which locks the folio, enforces permissions, applies business-date posting guards, writes `FolioTransaction`, and records `FinancialAuditEvent`. Higher-level services wrap it for staff posting, reversals, nightly charges, gateway payments, refunds, catch-up charges, and checkout closing.

Night Audit posts nightly accommodation and tax through `Folios::PostNightlyCharges`, with `night_audit_id`, metadata, and unique nightly posting keys. Checkout flows through `Bookings::TransitionStatus#check_out`, which calls `Folios::CloseForCheckout` before moving the booking to `completed`.

Priority #1 financial safety hardening is now in place for catch-up idempotency, backdated catch-up posting dates, required DB fields, touched override-param paths, and checkout local payment/refund sync readiness. The remaining gaps are mostly broader lifecycle policy and coverage areas: creation timing, cancellation/no-show edge cases, remaining closed-date override surfaces, and end-to-end request coverage.

## Missing Core Pieces

- Explicit folio lifecycle rules beyond open/closed.
- Controlled folio reopen service and route.
- First-class transaction code configuration if categories are not sufficient.
- Full cancellation folio policy.
- Consistent reason requirements for write-offs, manual adjustments, refunds, and reopen.
- Backdated check-in/reinstate integration specs.
- Broader rollback tests for posting failures during lifecycle transitions.

## Dangerous Or Risky Current Behavior

- Some non-touched flows still expose or pass explicit override options, including check-in/reinstate paths; the touched reversal/checkout/backdated catch-up paths were cleaned up.
- Manual booking creation does not clearly create a folio until check-in, which can leave confirmed bookings without folios until later.
- Night audit skips checked-in bookings with no folio instead of repairing them; post-close evaluation can block, but no automatic folio repair is evident.
- Cancellation changes booking/inventory state without clear folio close, refund, or charge policy.
- Security deposits are linked to folios but not included in `outstanding_balance`, which is probably correct for liability treatment but needs explicit policy.
- Checkout sync can persist local payment/refund folio transactions before checkout later fails on recalculated balance; this is intentional local sync behavior but should be operationally understood.
- Financial summary relies on `posting_date` totals and needs stronger tests around reversals, refunds, write-offs, and audit retry scenarios.

## Recommended Build Order

1. Establish and document in code the single booking folio lifecycle: when folios are created, opened, closed, and terminal.
2. Harden transaction categories or add transaction codes if operational configuration is needed.
3. Keep forecasted charges separate from posted folio transactions and strengthen forecast actualization tests.
4. Preserve posted transaction immutability and reversal-only correction behavior.
5. Keep business date and currency required on all folio transactions at DB and model level.
6. Keep idempotency keys and DB duplicate protection for every automated posting path; catch-up is now column/index backed.
7. Keep Night Audit-posted transactions linked through `night_audit_id`; add stronger financial summary tests.
8. Continue centralizing posting through `Folios::InsertTransaction`; avoid controller/model direct writes.
9. Continue hardening checkout readiness around synced captured payments and completed refunds; local sync now runs before close.
10. Add controlled folio close/reopen rules with permissions, reason, and financial audit events.
11. Standardize reason requirements for sensitive financial actions and remove trust in staff-supplied bypass flags.
12. Add high-value tests around Night Audit, checkout, backdated check-in, no-show/reinstate, payments/refunds, duplicate prevention, and rollback behavior.
