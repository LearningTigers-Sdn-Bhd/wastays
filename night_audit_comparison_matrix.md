# Night Audit Comparison Matrix

## 1. Summary

The current Night Audit is **MVP-ready with follow-up hardening recommended**. Its accounting posting core is strong: nightly room/tax charges are limited to in-house `checked_in` stays, duplicate postings are protected by a database unique index, folio transactions are immutable, retries reuse the same audit row, and hotel business dates are locked during execution.

The Night Audit is **MVP-ready with follow-up hardening recommended**. It now moves stale checked-in bookings to `review_due_out`, records those changes with Night Audit metadata, skips normal nightly charges for due-out reviews, and stores run-specific status changes, posted charges, skipped items, and failed items. Operational review states such as `review_due_out` are warning-only and do not prevent close. Accounting integrity issues, including a missing folio for a chargeable booking, remain hard blockers. Run-result rebuilding tolerates orphaned historical booking audit logs, so retry/close is not blocked when an old audit log points at a booking row that no longer exists. Business-date governance is based on one current accounting business date per hotel, where current statuses are `open`, `audit_running`, and `audit_blocked`; clock-derived dates are expected-date calculations, not posting authority.

| Overall Area | Assessment | Notes |
|---|---|---|
| Booking Status Flow | MVP-ready with a recovery gap | Missed arrivals move to `review_no_show`; stale checked-in bookings move to `review_due_out` as a Night Audit safety net. Amending a `review_no_show` arrival date still does not return it to `confirmed`. |
| Folio Posting | Strong but incomplete | Checked-in-only room/tax posting, immutable transactions, locks, posting-date controls, database duplicate protection, and run-level skipped/failed posting details exist. Direct relational `night_audit_id` linkage remains absent. |
| Business Date Closing | Strong | Audit claims and locks the hotel’s current accounting date, blocks unsafe posting, closes only after posting/evaluation, and atomically opens the next date. A partial unique index enforces one current accounting business date per hotel. |
| Audit Summary | MVP-ready | Stored `run_results` reconcile run-specific status changes, posted charges, skipped items, and failed items; operational and financial summaries remain available. Status-change rows tolerate missing historical booking records with fallback details. |
| Retry / Idempotency | Strong | Failed/blocked runs can retry; nightly/no-show charge keys and unique indexes prevent duplicate charges. Status changes completed before a later failure remain committed but are idempotently skipped on retry. Run-result rebuilding is nil-safe for orphaned booking audit logs. |
| Enterprise Features | Partially implemented / overbuilt for MVP | Force roll, journal batches, GL mapping, audit packets, deposit liability, occupancy, ADR, RevPAR, and advanced reports exist. Cashier/shift reconciliation, trial balance, city ledger, and audit reversal are absent. |

## 2. Booking Status Flow Matrix

| Area | Expected PMS Behavior | Current Implementation | Status | Notes / Gap |
|---|---|---|---|---|
| Missed arrival review | `confirmed` with passed arrival date becomes `review_no_show` | `NightAudits::ReviewMissedArrivals` changes confirmed arrivals for the audited date to `review_no_show` and stores `no_show_review_business_date`. | Implemented | Called by `NightAudits::ProcessNoShowReviews` from `NightAudits::Run`. |
| Missed departure review | `checked_in` with passed departure date becomes `review_due_out` | `NightAudits::ReviewDueOuts` transitions checked-in bookings due on or before the audited date; unresolved reviews are warnings while failed transitions leave stale checked-in blockers. | Implemented | Booking audit logs include `source: night_audit`, `night_audit_id`, and business date. |
| In-house overnight status | A checked-in guest staying overnight remains `checked_in` | No Night Audit status transition is applied to eligible overnight stays. | Implemented | `Folios::PostNightlyCharges#bookings_to_post` selects `checked_in` stays where checkout is after the business date. |
| Backdated check-in | `review_no_show` can become `checked_in` | `Bookings::TransitionStatus#check_in` supports `review_no_show` using event `backdated_check_in` and processes catch-up charges. | Implemented | Backdated controller restricts this action to `review_no_show`. |
| Mark no-show | `review_no_show` can become `no_show` | `Bookings::FinalizeNoShow` supports manual and automatic transition to `no_show`. | Implemented | Automatic finalization on a later Night Audit exceeds the requested MVP flow; see anomalies. |
| Cancel review no-show | `review_no_show` can become `cancelled` | `Bookings::TransitionStatus#cancel` includes `review_no_show` as cancellable. | Implemented | Inventory and assigned-room release are included. |
| Amend arrival date | `review_no_show` returns to `confirmed` when arrival date is amended | `Bookings::UpdateStayService` can amend dates but explicitly does not change status; lifecycle has no amend-arrival event from `review_no_show` to `confirmed`. | Missing | Amended booking remains `review_no_show`. |
| Checkout due-out review | `review_due_out` can become `completed` through checkout | `Bookings::TransitionStatus#check_out` accepts `review_due_out`. | Implemented | The status can be resolved if created through another operational path. |
| Extend due-out stay | `review_due_out` returns to `checked_in` after extending stay | `Bookings::ProcessLateCheckout` updates checkout date and transitions with `resolve_late_checkout`. | Implemented | Night Audit creates the review state when needed; staff resolves it by extending the stay. |
| Keep due-out for review | `review_due_out` may remain for review | No automatic transition away from an existing `review_due_out`. | Implemented | Existing review remains until staff resolves it. |
| No-show finality | `no_show` is final unless manually reinstated | Lifecycle permits only `reinstate`, and `Bookings::ReinstateReservation` performs a controlled reinstatement to `checked_in`. | Implemented | Manual reinstatement includes inventory, catch-up charges, and audit log. |
| Completed finality | `completed` is final unless privileged reopen exists | Lifecycle defines no transitions from `completed`. | Implemented | No privileged reopen was found. |
| Cancelled finality | `cancelled` is final unless manually reinstated | Lifecycle defines no transitions from `cancelled`; no cancelled reinstatement path was found. | Implemented | This is stricter than the optional reinstatement allowance. |
| Overbooked exception | `overbooked` remains a manual exception | Lifecycle only permits manual `resolve_overbooking` or cancel; Night Audit does not select it. | Implemented | No Night Audit auto-resolution found. |
| Pending exclusion | Pending bookings are not moved to `review_no_show` | Missed-arrival candidates use the `confirmed` scope only. | Implemented | No pending transition in Night Audit path. |
| Cancelled exclusion | Cancelled bookings are not changed by Night Audit | Night Audit candidate scopes do not include cancelled bookings. | Implemented | No automatic cancelled transition found. |
| Completed exclusion | Completed bookings are not changed by Night Audit | Completed bookings may be evaluated as financial blockers but are not status-changed. | Implemented | Completed bookings with missing timestamps/outstanding balances can block close. |
| Existing no-show exclusion | Existing `no_show` bookings are not changed by Night Audit | Later audits do not transition existing no-shows. | Implemented | Tests confirm later audit dates do not keep old no-shows financially relevant. |
| No direct confirmed to no-show | Night Audit must first use `review_no_show` | Current audit first moves confirmed arrivals to review; only older review records are auto-finalized later. | Partially Implemented | No same-run direct transition, but automatic later finalization is not the requested staff-review behavior. |
| No direct checked-in to completed | Night Audit must not check guests out | Night Audit does not transition checked-in bookings to completed. | Implemented | Due-outs first move to warning-only `review_due_out`; only failed transitions leave stale checked-in blockers. |
| Status-change actor/source | Store who/what caused changes | Booking audit logs store optional user, source, old/new values, event, `night_audit_id`, and business date for missed arrivals/no-shows. | Implemented | `BookingAuditLog` is immutable. Scheduled runs use a system/nil actor. |
| Status-change audit log | Create audit log for status changes | `Bookings::RecordAuditLog` is used for review, no-show, check-in, checkout, cancel, reinstate, and due-out resolution. | Implemented | Review/no-show entries explicitly reference Night Audit where applicable. |

## 3. Folio / Charge Posting Matrix

| Area | Expected PMS Behavior | Current Implementation | Status | Notes / Gap |
|---|---|---|---|---|
| Checked-in room charge | Post room charge for checked-in bookings only | `Folios::PostNightlyCharges#bookings_to_post` selects only `checked_in` stays covering the audited night. | Implemented | Checkout-day charge is excluded. |
| Tax/service charge | Post configured tax/service charge | `post_tax_charges` posts tax lines from `tax_posting_snapshot` or configured booking tax lines. | Implemented | No separate generic service-charge category was found. |
| Package/fixed/recurring charges | Post configured package/fixed/recurring charges | Night Audit posts accommodation and tax only. | Not Needed for MVP | Add later if packages/recurring inclusions become product requirements. |
| Pending exclusion | Do not post normal room charge for pending bookings | Pending is excluded by checked-in-only scope. | Implemented |  |
| Confirmed exclusion | Do not post normal room charge for confirmed bookings | Confirmed is excluded by checked-in-only scope. | Implemented |  |
| Review no-show exclusion | Do not post normal room charge for `review_no_show` | Review no-show is excluded from nightly room posting. | Implemented | Older reviews may receive separately categorized no-show charges when auto-finalized. |
| Review due-out policy | Post only if still in-house for audited date by policy | `review_due_out` is intentionally excluded from normal nightly posting; staff must checkout or extend the stay back to `checked_in`. | Implemented | A future Night Audit posts normal charges after an extension creates new eligible nights. |
| No-show exclusion | Do not post normal room charge for `no_show` | No-show is excluded; `Bookings::FinalizeNoShow` posts a separate `no_show_charge`. | Implemented |  |
| Cancelled exclusion | Do not post normal room charge for cancelled bookings | Cancelled is excluded by checked-in-only scope. | Implemented |  |
| Completed exclusion | Do not post normal room charge for completed bookings | Completed is excluded by checked-in-only scope. | Implemented |  |
| Room-charge duplicate protection | Prevent duplicate nightly room charges | Application lookup plus unique partial index on `booking_folio_id` and metadata `nightly_charge_key`. | Implemented | Key contains booking, stay date, charge kind, and room/tax identity. |
| Tax duplicate protection | Prevent duplicate nightly tax charges | Tax postings use the same `nightly_charge_key` strategy and unique index. | Implemented | Separate tax identities permit multiple valid tax lines. |
| Audit-run linkage | Link posted charges to `audit_run_id` | Nightly transaction metadata stores `night_audit_id`; there is no direct foreign-key column/association on `folio_transactions`. | Partially Implemented | Metadata linkage is queryable but lacks referential integrity. |
| Business-date linkage | Link posted charges to business date | `posting_date` is a required date column and is set to the audited business date; metadata also stores `stay_date`. | Implemented | `posting_date` functions as the folio transaction business date. |
| Folio linkage | Link charges to `folio_id` | Required `booking_folio_id` foreign key. | Implemented |  |
| Booking linkage | Link charges to `booking_id` | Booking is linked through required folio association and also copied into metadata. | Implemented | No direct booking foreign key on transaction, but relational path is enforced. |
| Posting source | Record source as `night_audit` | Stored in transaction metadata and financial audit event source. | Implemented | Source is not a dedicated folio transaction column. |
| Transaction code/type | Record transaction code/type | Required `transaction_type`, required category, and optional `gl_code` are stored. | Implemented | Categories act as transaction codes; GL mappings are also supported. |
| Retry without duplicate charges | Retry safely | Existing charge lookup and database unique index make re-posting idempotent. | Implemented | Tests cover retry/duplicate behavior and forecast actualization. |
| Skipped charge tracking | Store skipped charges and reason | Duplicate-protected nightly charges are actualized and recorded as skipped items with stable keys and reasons. Missing folios are surfaced as accounting blockers rather than posting skips. | Implemented | Duplicate-protected skips do not block close. |
| Failed charge tracking | Store failed charges and error reason | Item-level posting failures and overall audit failures are retained in logs and `run_results`. | Implemented | Failed posting prevents clean close. |
| Forecast handling | Do not mutate forecasts directly into posted transactions | A new immutable folio transaction is created, then the forecast is marked `actualized` and linked to it. | Implemented | Forecast status is mutated appropriately; it is not reused as the ledger posting. |
| Posted transaction immutability | Posted transactions are immutable | `FolioTransaction` prevents financial-field updates and destruction. | Implemented | Only `voided_by_transaction_id` may be added later. |
| Manual adjustment | Adjustment is a separate transaction | Adjustment transaction types/categories are supported through posting services. | Implemented | Original posting is not overwritten. |
| Manual void/reversal | Void uses a separate reversal/status | `Folios::ReverseTransaction` creates a reversal transaction and links the original as voided. | Implemented | Reversal requires reason/note. |
| Nightly rate source | Use locked nightly/stay-date rate | `NightlyChargeCalculation` uses `nightly_rate_snapshot` when present, with legacy subtotal-average fallback. | Partially Implemented | Legacy fallback is not a fully locked nightly rate. |
| Tax policy date | Use configured tax policy for business date | Tax posting snapshot is keyed by stay/business date, with booking tax-line fallback. | Partially Implemented | Fallback may not represent policy changes effective on a specific business date. |
| Posting date correctness | Do not use current calendar date for Night Audit posting | Nightly posting explicitly uses `@business_date`. | Implemented |  |
| Timezone correctness | Do not use server timezone incorrectly | Hotel business windows and booking date scopes use the hotel time zone. | Implemented | Nightly SQL compares timestamp casts to the supplied business date; dedicated timezone tests exist around audit scheduling/windows. |

## 4. Business Date Closing Matrix

| Area | Expected PMS Behavior | Current Implementation | Status | Notes / Gap |
|---|---|---|---|---|
| Separate hotel business date | Business date is separate from calendar date | `HotelBusinessDate` and hotel-specific `business_date_for`/business-day windows exist. | Implemented | Hotel timezone and configurable start/end times are used. |
| Close current business date | Night Audit closes the current business date | Successful audit transitions `audit_running` to `closed` or `force_closed`. | Implemented |  |
| Open next business date | Open the next date after close | `HotelBusinessDate#open_next_business_date!` creates/reuses the next open date. | Implemented | Runs after close inside the final transaction. |
| One current accounting date per hotel | Only one row across `open`, `audit_running`, and `audit_blocked` may be current | A PostgreSQL partial unique index on `hotel_id` enforces the current-status invariant. | Implemented | Clock-derived dates remain scheduling/default calculations and never grant posting authority. |
| One completed run per hotel/date | Only one completed audit run | Unique index on `night_audits(hotel_id, business_date)` and completed rerun rejection. | Implemented | Same row is reused for blocked/failed retry. |
| Concurrent-run prevention | Same hotel/date cannot run twice concurrently | Business-date row is claimed under `with_lock`; `audit_running` rejects the second run. | Implemented | Database uniqueness also protects initial row creation. |
| Completed rerun prevention | Completed audit cannot freely rerun | Service rejects any completed audit; controller also rejects unless force requested, but service still rejects it. | Implemented |  |
| Failed retry | Failed audit can retry safely | Failed/blocked audit row is reused; business date can transition from `audit_blocked` to `audit_running`; postings are idempotent. | Implemented | Scheduled job re-enqueues failed/blocked audits. |
| Audit statuses | Pending, running, failed, completed | Model supports `pending`, `running`, `failed`, `completed`, and `blocked`. | Implemented | Additional blocked state is useful. |
| Started timestamp | Store `started_at` | Set when run starts. | Implemented |  |
| Completed timestamp | Store `completed_at` | Set on completed, blocked, and failed outcomes. | Implemented | For blocked/failed, field means execution ended, not business date closed. |
| Started-by actor | Store `started_by_id` | `performed_by_user_id` records the initiating user; scheduled runs allow nil/system. | Implemented |  |
| Completed-by actor | Store `completed_by_id` if applicable | No distinct completed-by field. | Missing | Same actor generally performs the run, but completion actor is not separately represented. |
| Business date field | Audit run stores business date | Required `night_audits.business_date`. | Implemented |  |
| Hotel field | Audit run stores hotel | Required `hotel_id`. | Implemented |  |
| Failure error | Store `error_message` when failed | Error is stored in `NightAuditLog.metadata` and `FinancialAuditEvent.metadata`; no `night_audits.error_message` field. | Partially Implemented | Failure reason is retained but not directly on the run. |
| Summary snapshot | Store run summary/snapshot | JSON summary, blockers, exceptions, separate financial summary, and run-specific posting/skipped/failed details are persisted. | Implemented |  |
| Dangerous-change lock | Prevent dangerous changes during execution | `FinancialControls::PostingGuard` blocks non-audit folio posting while `audit_running`; booking/status/date edits are not generally locked. | Partially Implemented | Financial posting is protected, but operational changes can race with evaluation/status processing. |
| Critical failure close prevention | Do not close if critical posting fails | Posting errors fail the audit and move business date to `audit_blocked`; post-evaluation blockers prevent close. | Implemented |  |
| Partial-failure recovery | Recover without duplicate posting | Charges/status changes may remain committed before a later failure, but retries reuse unique posting keys and idempotent status scopes. | Implemented | No per-item recovery ledger; operational changes remain committed by design. |
| Close ordering | Close after successful posting | Posting and post-close evaluation occur before business-date close. | Implemented |  |
| Next-date ordering | Open next date only after current closes | Close and next-date open occur in the same final database transaction. | Implemented |  |

## 5. Audit Summary / Reporting Matrix

| Area | Expected PMS Behavior | Current Implementation | Status | Notes / Gap |
|---|---|---|---|---|
| Moved to review-no-show count | Show number moved by this run | Summary stores total current `review_no_show` count, while the process-start log stores this run's reviewed count. | Partially Implemented | Main summary can overstate the run-specific count. |
| Moved to review-due-out count | Show number moved by this run | `summary.run_results.status_changes` records affected bookings and transitions, including `checked_in` to `review_due_out`. | Implemented |  |
| Orphaned booking audit logs | Preserve historical status-change evidence even if the booking row is gone | `NightAudits::BuildRunResults` keeps the status-change item with original booking id and fallback guest/reference fields instead of crashing. | Implemented | Prevents retry failures such as `undefined method 'confirmation_token' for nil`. |
| Room charges posted count | Show count posted | `summary.run_results.charges_posted` stores count, total, and transaction details. | Implemented |  |
| Total room revenue | Show room revenue total | `NightAuditFinancialSummary.room_revenue` stores all accommodation postings for the business date. | Implemented | It is a business-date total, not strictly charges created by the audit run. |
| Total tax/service charge | Show tax/service total | `tax_revenue` is stored. | Implemented |  |
| Skipped bookings | Show skipped bookings | Run results store skipped posting/review items. | Implemented |  |
| Skip reason | Show reason | Item-level Night Audit logs and run results store skip reasons. | Implemented |  |
| Duplicate-protected skips | Show duplicate skips | Duplicate-protected nightly charges are recorded as skipped with stable item keys. | Implemented |  |
| Failed items | Show failed items | Item-level failures and overall audit failures are stored in run results. | Implemented |  |
| Failure reason | Show failure reason | Overall error is retained in Night Audit log and financial audit event metadata. | Partially Implemented | Not surfaced as a dedicated run field/item list. |
| Audit operator | Show who ran audit | View shows `performed_by_user` or System. | Implemented |  |
| Start/completion times | Show `started_at` and `completed_at` | Stored and displayed. | Implemented |  |
| Business date | Show business date | Stored and displayed. | Implemented |  |
| Hotel/property | Show hotel/property | Audit belongs to hotel; audit packet/service has property context. | Implemented |  |
| Stored summary | Persist after completion | Summary, blockers, exceptions, and financial summary are stored. | Implemented | Also stored for blocked/failed outcomes where available. |
| Historical viewing | View later | Index/show pages and persisted records support later viewing. | Implemented |  |
| Database reconciliation | Summary matches actual database records | Financial totals are calculated from folio transactions by posting date and can be recalculated with changelog. Operational counts are snapshot counts, not run-specific reconciliation. | Partially Implemented | Main summary does not prove which postings/status changes came from the run. |
| Export/print | Export or print if implemented | Completed audit has a PDF audit packet export. | Implemented |  |
| Separate status/posting results | Separate booking changes from folio postings | Operational and financial summaries are separate, and `run_results` retains run-specific status-change, posting, skipped, and failed item lists. | Implemented |  |
| Warnings vs critical failures | Separate warnings from blockers | `exceptions` and `blocked_details` are separate and displayed separately. | Implemented |  |

## 6. Close Policy Matrix

Core rule: Night Audit may close when unresolved items are controlled operational review states, but it must not close when accounting integrity is incomplete. If the system cannot prove that a booking is non-chargeable, it must treat the accounting issue as a blocker.

| Condition | Close Policy | Current Enforcement |
|---|---|---|
| Existing `review_due_out` | Allow close with warning | Returned under `exceptions["review_due_out"]`; excluded from `blocked_details` and normal nightly posting. |
| Existing `review_no_show` | Allow close with review visibility | Remains an operational review state unless a separate configured workflow resolves it. |
| Stale checked-in due-out successfully changed to `review_due_out` | Allow close with warning | `NightAudits::ReviewDueOuts` runs before evaluation/posting; successful transitions appear as run-specific status changes and warnings. |
| Stale checked-in due-out that failed to transition | Block close | Booking remains `checked_in` and is returned under `blocked_details["due_out_not_checked_out"]`; failed transition is retained in run results. |
| Duplicate-protected nightly charge skip | Allow close | Existing charge is recorded as a skipped item and accepted as idempotent completion. |
| Open housekeeping, complaint, or unusual in-house folio-balance review | Allow close with warning | Returned under `exceptions`; warnings do not affect the close decision. |
| Missing folio for checked-in or otherwise chargeable/current financially relevant booking | Block close | Returned under `blocked_details["missing_folio"]` after posting-phase evaluation. |
| Missing folio for proven non-chargeable booking such as `cancelled` or `no_show` | Allow close | Proven non-chargeable states are excluded from the missing-folio blocker; ambiguous states remain blocking. |
| Missing nightly room/tax charge | Block close | Returned under `blocked_details["missing_nightly_charges"]`. |
| Failed posting | Block/fail close | Item-level failure and overall audit failure are retained; business date does not advance. |
| Outstanding due-out/completed folio balance | Block close | Returned under `blocked_details["outstanding_folio_balance"]`. |
| Unsynced captured payment or completed refund | Block close | Returned under `captured_payment_not_synced` or `refund_not_synced`. |
| Ambiguous or non-current business-date authority | Block close | `HotelBusinessDate` current-record checks reject the run and prevent date advancement. |
| Orphaned historical audit log with fallback details | Allow close | Run-result rebuilding preserves fallback details without requiring the deleted booking row. |

## 7. Optional Enterprise Features Matrix

| Area | Expected PMS Behavior | Current Implementation | Status | Notes / Gap |
|---|---|---|---|---|
| Cashier reconciliation | Reconcile cashier activity | No hotel Night Audit cashier reconciliation found. | Not Needed for MVP | Admin payment-issue reconciliation is a different workflow. |
| Cash drawer variance | Expected versus actual cash | No cash drawer/variance workflow found. | Not Needed for MVP |  |
| Payment method reconciliation | Reconcile totals by method | Payments exist, but no Night Audit payment-method reconciliation report found. | Not Needed for MVP |  |
| Cash payment summary | Summarize cash payments | Financial summary has total payments only; no dedicated Night Audit cash summary. | Not Needed for MVP |  |
| Card payment summary | Summarize card payments | No dedicated Night Audit card summary found. | Not Needed for MVP |  |
| Bank transfer summary | Summarize bank transfers | No dedicated Night Audit bank-transfer summary found. | Not Needed for MVP |  |
| OTA payment summary | Summarize OTA payments | No dedicated Night Audit OTA payment summary found. | Not Needed for MVP |  |
| Refund report | Report refunds | Night Audit financial summary includes refund total; broader refund workflows exist. | Partially Implemented | No dedicated Night Audit itemized refund report identified. |
| Void report | Report voids/reversals | Reversals and manual adjustments/voids display exist on the audit page. | Partially Implemented | No dedicated standalone void report identified. |
| Deposit ledger | Deposit liability ledger/report | Deposit liability report with CSV/XLS/PDF exports exists. | Implemented | Enterprise reporting outside core Night Audit. |
| Guest ledger | Guest ledger | Folio ledger/reporting exists, but no explicit guest-ledger close workflow found. | Partially Implemented |  |
| Trial balance | Produce trial balance | No trial balance found. | Not Needed for MVP |  |
| City ledger transfer | Transfer receivables to city ledger | No city ledger found. | Not Needed for MVP |  |
| Manager approval workflow | Approval for close/override | Permission is required for force roll/financial-date override, but no multi-step approval workflow exists. | Partially Implemented |  |
| Force close | Force close unresolved exceptions | Force roll/`force_closed` business-date state exists with permission and audit events. | Implemented | Enterprise feature already present. |
| Reopen closed date | Reopen a closed business date | `reopened` is not exposed or relied on for MVP. | Not Needed for MVP | Add only with a complete permissioned and audited workflow. |
| Audit reversal | Reverse a completed Night Audit | No audit reversal workflow found. | Not Needed for MVP | Individual folio postings can be reversed. |
| Housekeeping sync | Sync room status | Checkout/no-show room status operations exist; Night Audit treats open housekeeping requests as warnings. | Partially Implemented | No complete Night Audit housekeeping sync step. |
| Revenue by transaction code | Detailed revenue by code | GL mapping, journal batches, categories, and report exports exist. | Implemented |  |
| Occupancy report | Occupancy reporting | Daily occupancy and manager flash reports with exports exist. | Implemented |  |
| ADR report | ADR reporting | Daily occupancy and manager flash reports calculate/export ADR. | Implemented |  |
| RevPAR report | RevPAR reporting | Daily occupancy and manager flash reports calculate/export RevPAR. | Implemented |  |
| No-show fee automation | Automatically post no-show fee | Older `review_no_show` bookings are auto-finalized and charged on a later Night Audit. | Implemented | This is overbuilt/risky relative to the requested staff-review MVP behavior. |
| Package/fixed charge posting | Post package/fixed charges | Not found in Night Audit posting. | Not Needed for MVP |  |
| POS integration | Integrate POS charges | No POS integration found. | Not Needed for MVP |  |
| Multi-shift close | Close multiple shifts | No multi-shift close found. | Not Needed for MVP |  |
| Shift/cashier close prerequisite | Require shift close before Night Audit | Not found. | Not Needed for MVP |  |
| Manager adjustment report | Report manual adjustments | Night Audit page displays manual adjustments/voids; financial summary stores adjustment total. | Implemented |  |
| Tax report | Dedicated tax report | Tax totals exist in audit/revenue reports, but no dedicated tax report found. | Partially Implemented |  |
| Revenue center report | Revenue center reporting | GL/category reporting exists, but no explicit revenue-center report found. | Not Needed for MVP |  |
| A/R or company ledger transfer | Transfer to A/R/company ledger | Not found. | Not Needed for MVP |  |

## 8. Gaps Found

| Priority | Gap | Risk | Recommendation |
|---|---|---|---|
| High | Business-date authority must remain centralized in `HotelBusinessDate`. | Reintroducing clock-derived posting defaults would bypass the one-current-accounting-date invariant. | Keep financial posting governed by `hotel.current_business_date_record`; use clock-derived dates only for expected-date calculation and scheduling. |
| High | Charge linkage to Night Audit is metadata-only. | `night_audit_id` has no relational integrity and could become invalid or omitted by alternate posting paths. | Add a nullable `night_audit_id` foreign key or a dedicated audit-posting join/event record while retaining metadata for readability. |
| High | Booking/status/date changes are not generally locked while Night Audit runs. | Operational edits can race with candidate selection and post-close evaluation. | Add a targeted operational guard for financially relevant booking changes during `audit_running`, with controlled blocker-resolution overrides. |
| Medium | `review_no_show` cannot return to `confirmed` when arrival date is amended. | Staff cannot complete the expected missed-arrival recovery flow cleanly. | Add an explicit audited lifecycle event for amend-arrival-date review resolution. |
| Medium | Failed audit error is not stored directly on the run. | Failure discovery relies on log/event lookup and is harder to query/report. | Add a run-level failure field or structured failure summary. |
| Medium | No distinct `completed_by_id`. | Completion/force-close accountability is less explicit if execution actor differs from initiator. | Add only if asynchronous/operator handoff requires it. |
| Medium | Nightly rate and tax posting allow legacy fallbacks rather than requiring locked date snapshots. | Historical amounts may depend on averaged/current booking data for legacy records. | Require snapshots for new bookings and flag legacy fallback use in the audit summary. |
| Low | No dedicated service-charge posting category. | Configured service charges may not be represented separately from tax. | Add only when service-charge configuration exists. |
| Later | No cashier/shift reconciliation, trial balance, city ledger, POS integration, or audit reversal. | Limits enterprise accounting operations but does not block MVP. | Defer until core MVP status and reconciliation gaps are fixed. |

## 9. Anomalies Detected

| Severity | Area | Anomaly | Why It Is a Problem | Evidence / File Reference | Recommendation |
|---|---|---|---|---|---|
| High | Reporting | The displayed `review_no_show_count` is the total number currently in review, not the number moved by that audit run. | Historical or pre-existing review records can make the summary claim more status changes than the run performed. | `app/services/night_audits/evaluate.rb#build_summary`; run-specific count exists only in process-start log metadata in `NightAudits::Run`. | Store and display run-specific transition counters; label snapshot counts separately. |
| High | Business date governance | The required invariant is one current accounting business date per hotel across `open`, `audit_running`, and `audit_blocked`. | More than one current row creates ambiguous accounting authority. | `HotelBusinessDate::CURRENT_STATUSES` and the partial unique current-date index define and enforce the invariant. | Preserve the database constraint and authoritative Hotel helpers. |
| Medium | No-show workflow | A later Night Audit automatically finalizes every expired `review_no_show` and posts no-show charges. | The requested flow expects staff review actions; automatic charging/status finalization can create disputes when a booking is still awaiting resolution. | `NightAudits::ProcessNoShowReviews#finalize_expired_reviews`; `Bookings::FinalizeNoShow`; test “keeps an expired review finalized when the audit later fails”. | Make auto-finalization an explicit hotel policy/enterprise option; default MVP to staff resolution. |
| Medium | Partial failure behavior | Missed-arrival/no-show status changes and charges remain committed when a later audit phase fails. | Retry is financially idempotent, but operators may see a failed audit that already changed bookings/posted no-show fees without a clear itemized partial-work summary. | `NightAudits::Run` performs no-show processing before evaluation; specs confirm review/no-show changes persist after failure. | Record completed steps and affected items on the failed run; clearly display partial completion. |
| Resolved | Reporting | Orphaned booking audit logs previously crashed run-result rebuild. | A deleted/missing booking referenced by a historical `BookingAuditLog` could make retry fail after blockers were already resolved. | `NightAudits::BuildRunResults#status_changes`; regression spec covers a missing auditable booking. | Fixed by preserving the item with fallback booking details. |
| Medium | Reporting | Financial summary totals all transactions posted to the business date, not specifically transactions created by the Night Audit run. | The total can be correct for business-day revenue but cannot reconcile “charges posted by this audit,” and manual postings may be mistaken for audit postings. | `NightAudits::CalculateFinancialSummary` filters only hotel and `posting_date`; no `night_audit_id` filter. | Present separate business-day totals and run-posted totals. |
| Medium | Operational concurrency | Folio posting is locked, but booking timeline/status edits can occur during `audit_running`. | Candidate sets and evaluation results can change mid-run. | `FinancialControls::PostingGuard` protects financial posting only; no equivalent general booking guard found. | Block or version-check relevant booking timeline/status edits while the date is in audit. |
| Low | Model/workflow consistency | Reopening is intentionally excluded from MVP. | A reopen state without a complete workflow would weaken close authority. | `HotelBusinessDate::STATUSES` excludes `reopened`. | Implement reopening only as a later permissioned and audited workflow. |

## 10. Recommended MVP Scope

| MVP Feature | Required? | Current Status | Recommendation |
|---|---|---|---|
| Booking status review | Yes | Implemented | Retain missed-arrival and fallback due-out review behavior. |
| `confirmed` to `review_no_show` | Yes | Implemented | Retain current audited transition. |
| `checked_in` to `review_due_out` | Yes | Implemented | Retain idempotent fallback review and warning behavior. |
| Checked-in overnight remains checked-in | Yes | Implemented | Retain. |
| Room charge posting for checked-in bookings | Yes | Implemented | Retain checked-in-only scope; document due-out policy. |
| Tax/service charge posting if configured | Yes | Partially Implemented | Tax is implemented; add service charge only if configuration exists. |
| Duplicate charge protection | Yes | Implemented | Retain application check, folio lock, and database unique index. |
| Business date close | Yes | Implemented | Preserve the one-current-accounting-date invariant. |
| Open next business date | Yes | Implemented | Retain transactional ordering. |
| Audit run record | Yes | Implemented | Add structured run failure/result fields only as needed for reconciliation. |
| Audit summary | Yes | Implemented | Retain run-specific posting/status/skipped/failed counters and item details. |
| Skipped item tracking | Yes | Implemented | Retain stable item keys and deduplication across retries. |
| Failed item tracking | Yes | Implemented | Retain item-level and overall failure reasons. |
| Failed audit retry safety | Yes | Implemented | Retain current idempotency, orphaned audit-log tolerance, and explicit retry/partial-work visibility. |
| Prevent concurrent audit run | Yes | Implemented | Retain business-date row lock and unique audit row. |
| Audit log for status changes and folio postings | Yes | Implemented | Retain immutable booking/financial audit logs; strengthen direct run linkage. |

Recommended MVP flow:

```text
Start Night Audit
    |
    |- Step 1: Check booking statuses
    |     |- confirmed -> review_no_show
    |     `- checked_in due-out -> review_due_out
    |
    |- Step 2: Post nightly room/tax charges
    |     `- eligible in-house bookings, with database idempotency
    |
    |- Step 3: Reconcile run results and critical failures
    |
    |- Step 4: Close current business date and open next date
    |
    `- Step 5: Store and show run-specific summary
```

Do not require cashier reconciliation, trial balance, city ledger, deposit ledger, POS integration, audit reversal, advanced reports, housekeeping sync, force close, or manager approval workflow for MVP.

## 11. Recommended Later Scope

| Later Feature | Why It Matters | Suggested Priority |
|---|---|---|
| Configurable no-show fee automation | Allows properties to opt into automated finalization without forcing the policy on MVP users. | High Later |
| Manager approvals for force roll/reopen | Adds controlled accountability for exceptional close operations. | High Later |
| Trial balance | Supports formal accounting close and debit/credit validation. | High Later |
| Cashier reconciliation and payment variance | Reconciles cash/card/transfer totals against expected collections. | High Later |
| Guest ledger | Provides enterprise receivable visibility by guest/folio. | Medium Later |
| City ledger / A/R transfer | Supports company/direct-bill receivables. | Medium Later |
| Tax report | Gives tax-specific filing and reconciliation support. | Medium Later |
| Void/refund report | Improves manager review of corrections and leakage. | Medium Later |
| Package/fixed/recurring charge posting | Supports inclusive packages and recurring extras. | Medium Later |
| Reopen closed business date | Enables controlled correction workflows with full approval/audit controls. | Medium Later |
| Audit reversal | Supports full rollback only after robust ledger and approval design exists. | Low Later |
| Multi-shift and cashier close prerequisite | Supports larger properties with shift-based controls. | Low Later |
| POS integration | Consolidates outlet charges into the guest folio/business date. | Low Later |
| Housekeeping sync | Improves operational handoff at close. | Optional |
| Advanced revenue center reports | Supports departmental performance analysis. | Optional |
| Occupancy / ADR / RevPAR enhancements | Existing reports can be expanded after MVP reconciliation is reliable. | Optional |

## 12. Final Recommendation

Final status: MVP-ready

Recommended next action:

1. Preserve one current accounting business date per hotel across `open`, `audit_running`, and `audit_blocked`, and add targeted protection against booking timeline/status races during audit execution.
2. Add explicit `review_no_show` arrival-amendment resolution and make automatic no-show finalization a configurable later feature.
3. Preserve the implemented due-out fallback, run-specific results, posting idempotency, immutable folio ledger, business-date lock, posting guard, and retry behavior.

Do not build additional enterprise features yet unless the MVP status-flow and reconciliation issues are fixed.
