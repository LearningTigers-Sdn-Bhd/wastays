# E-Invoice Feature Update — Implementation Plan

**Branch:** `feat/e-invoice`
**Created:** 2026-06-24
**Status:** Completed

---

## Requirements

1. **Req ①** E-invoice must be issued (when requested by the guest) **after conclusion of payment** (which may be at booking, not checkout).
2. **Req ②** Guest can request an e-invoice within the **same calendar month** as the payment; WAStays auto-issues it (or on behalf of the hotel).
3. **Req ③** Un-requested e-invoices must be submitted to LHDN as a **consolidated batch within 7 days after month-end**, only for transactions **below RM 10,000**.
4. **Req ④** Any transaction **≥ RM 10,000** must have its own **individual e-invoice** — cannot be consolidated.
5. **Post-payment adjustments:** If folio balance differs from original invoice (extras / refunds), issue **Debit Note (03)** or **Credit Note (02)** referencing the original UUID.

---

## Design Decisions

| Decision | Answer |
|---|---|
| Consolidated buyer details | Use LHDN-prescribed generic: TIN `EI00000000010`, name `General Public`, all other fields `NA`, state `17`. Already defined as `GENERAL_CONSUMER_TIN` in `DocumentBuilder`. |
| ≥RM10k auto-issue timing | Immediately on payment conclusion. `resolved_fund_collector` already works at payment time; `SubmissionContext` raises gracefully when `unknown`. |
| Same-month reference date | Payment date (payment is the taxable event). |
| Post-payment adjustments | Debit Note (03) for increases, Credit Note (02) for refunds — LHDN's prescribed approach. |

---

## Tasks

### Task 1 — Schema Migration
- [x] Add columns to `e_invoice_submissions`:
  - `requested_by_guest` (boolean, default false)
  - `requested_at` (datetime)
  - `consolidated` (boolean, default false)
  - `consolidation_batch_id` (uuid)
  - `payment_concluded_at` (datetime)
  - `original_invoice_internal_id` (string) — references original invoice when this submission is an adjustment
- [x] Add index on `consolidation_batch_id`
- [x] Add index on `[status, consolidated, payment_concluded_at]`

### Task 2 — Refactor "Folio Closed" Guard → "Payment Concluded" Guard
- [x] `EInvoice::Submit` (`submit.rb`): Replace `folio_closed?` with `payment_concluded?`
- [x] `EInvoiceSubmissionsController#create`: Remove folio status check
- [x] `EInvoice::DocumentBuilder`: Use `payment_concluded_at` fallback for issue date/time
- [x] Add `Booking#payment_concluded_at` method (derive from payment_transactions if not stored)

### Task 3 — ≥RM10,000 Auto-Issue
- [x] New job `EInvoice::AutoIssueJob` — enqueue on payment completion for bookings with `total_amount >= 10_000`
- [x] Skip if already has valid guest-facing submission
- [x] Handle `unknown` fund_collector gracefully (already handled via ConfigurationError)
- [x] Hook into payment completion flow (where `payment_status` → `captured`)

### Task 4 — Guest E-Invoice Request Flow
- [x] New controller `Guest::BookingsEInvoiceController` with `#request` action
- [x] Validate: payment concluded + within same calendar month + no existing valid/requested submission
- [x] Enqueue `EInvoice::AutoIssueJob`
- [x] New route: `POST /guest/bookings/:id/request_e_invoice`
- [x] Guest portal view: "Request E-Invoice" CTA (visible only when conditions met)

### Task 5 — Consolidated Batch Submission
- [x] New service `EInvoice::ConsolidatedBatchBuilder`
  - Select un-requested paid bookings < RM 10k from previous month
  - Build single consolidated UBL document with generic buyer
  - Each booking becomes one `InvoiceLine` item
- [x] New job `EInvoice::MonthlyConsolidationJob`
  - Run 1st of each month at 00:05
  - For each hotel: collect qualifying bookings, build & submit batch
  - Mark all as `submitted` on success / `invalid` on reject
- [x] Tag pending bookings (< RM10k, not guest-requested) with `consolidated: true` at payment time

### Task 6 — Folio Close Adjustment (Debit/Credit Notes)
- [x] New service `EInvoice::AdjustmentNoteBuilder`
  - Build Debit Note (03) or Credit Note (02) referencing original submission UUID
- [x] Hook on folio close: compare original invoice amount vs final folio balance
- [x] New job `EInvoice::IssueAdjustmentJob`
- [x] Spec: `spec/services/e_invoice/adjustment_note_builder_spec.rb`

### Task 7 — Tests
- [x] `spec/services/e_invoice/submit_spec.rb` — payment-concluded guard
- [x] `spec/services/e_invoice/consolidated_batch_builder_spec.rb` — filtering, grouping, threshold
- [x] `spec/jobs/e_invoice/auto_issue_job_spec.rb` — ≥10k trigger, skip-if-exists, unknown fund_collector
- [x] `spec/requests/guest/bookings_e_invoice_request_spec.rb` — same-month validation, request creation
- [x] `spec/jobs/e_invoice/monthly_consolidation_job_spec.rb` — correct booking selection, batch submission
- [x] `spec/services/e_invoice/adjustment_note_builder_spec.rb` — adjustment note correctness

### Task 8 — Cron / Scheduler
- [x] Register `MonthlyConsolidationJob` in scheduler (cron: `5 0 1 * *`)

---

## Notes

- **Uniqueness constraint fix:** The original `booking_id` + `document_scenario` uniqueness constraint prevented adjustment notes (02/03) from coexisting with standard invoices (01). Updated scope to `[booking_id, document_scenario, document_type]` with a matching partial index.
- **Scheduler registration:** `MonthlyConsolidationJob` added to `config/recurring.yml` for both production and demo environments, running `cron 5 0 1 * *` (5 minutes past midnight on the 1st of every month).

---

## Execution Flow (after implementation)

```
Payment concludes (payment_status → captured)
    │
    ├── total_amount >= 10,000
    │     └── AutoIssueJob → individual e-invoice (01) immediately
    │
    └── total_amount < 10,000
          ├── Guest requests within same month
          │     └── AutoIssueJob → individual e-invoice (01) immediately
          │
          └── Guest does NOT request
                └── Tagged consolidated: true → Monthly job picks up
                      └── 1st of next month → consolidated batch submitted

Folio closes at checkout
    │
    ├── final_amount == original_invoice_amount → nothing
    ├── final_amount > original (extras)        → Debit Note (03) issued
    └── final_amount < original (refund/no-show)→ Credit Note (02) issued
```

---

## Remaining Sign-Off Before Marking Complete

**Updated:** 2026-06-25

The core logic is now in place and the latest regression suite is green, but we should still finish the following sign-off items before calling the feature fully complete:

### 1. Real-world scenario QA
- [ ] Verify end-to-end for WAStays-collected booking `< RM10,000` with no guest request → pending consolidated placeholder created
- [ ] Verify end-to-end for WAStays-collected booking `< RM10,000` with guest request in same month → individual invoice created, consolidated placeholder cancelled if it existed
- [ ] Verify end-to-end for hotel-direct booking `< RM10,000` with guest request → individual intermediary invoice created
- [ ] Verify end-to-end for booking `>= RM10,000` → individual invoice only, never consolidated
- [ ] Verify adjustment note flow for both debit note and credit note using real folio changes after original invoice validation

### 2. Scheduler / operations readiness
- [ ] Confirm `MonthlyConsolidationJob` is enabled in the actual deployed scheduler environment, not just committed in code
- [ ] Confirm staff know how to identify, retry, and monitor invalid or stale submissions from the hotel portal
- [ ] Confirm there is an operational playbook for month-end consolidation failures

### 3. Policy / product confirmation
- [ ] Confirm whether hotel staff should have a visible “issue on behalf of guest request” action for low-value bookings, since backend support now exists
- [ ] Confirm whether adjustment-note PDF/UI should also display `Original Total + Adjustment Amount = Revised Total` for human readability
- [ ] Confirm whether guest/public portals should ever expose adjustment-note downloads, or only the original invoice

### 4. Final regression pass before UI polish
- [ ] Run one final requirement-by-requirement manual audit against the live/staging behavior
- [ ] Recheck all e-invoice entry points after UI updates so no page reintroduces old selection logic between standard invoices (`01`) and adjustment notes (`02` / `03`)

### Current status

As of 2026-06-25, these logic areas are already covered and verified in test:
- Payment-concluded issuance logic
- Same-month guest request logic
- `< RM10,000` consolidated placeholder logic
- `>= RM10,000` individual-only logic
- Adjustment note issuance logic
- Adjustment-note PDF rendering
- Original invoice selection staying separate from adjustment notes
