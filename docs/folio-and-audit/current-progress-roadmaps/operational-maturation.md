# Active Roadmap: Operational Maturation

This roadmap outlines the remaining priorities required to transition from a functional foundation to a high-performance, operationally mature financial system.

---

## 1. Advanced Financial Controls & Governance
**Objective**: Introduce professional-grade financial oversight and fraud prevention.

- **Permission Segregation**: 
  - Completed May 20, 2026: folio posting no longer uses the broad `post_folio_transactions` permission.
  - Staff folio actions are now split into `post_folio_charges`, `post_folio_payments`, `execute_folio_refunds`, `post_folio_adjustments`, `post_folio_corrections`, and `post_folio_write_offs`.
  - Closed business-date override remains separately controlled by `override_financial_date_lock`.
- **Completed Financial Hardening**:
  - Completed May 20, 2026: `daily_revenue` report requests now require `view_reports` permission.
  - Completed May 20, 2026: journal batch creation fails fast when folio transactions are missing GL codes instead of excluding them from the batch.
  - Completed May 22, 2026: reporting expanded to include all charge categories (F&B, No-Show, Late Checkout, etc.) in `DailyRevenueReport` and `ManagersFlashReport`.
  - Completed May 22, 2026: granular folio permissions enforced at the service layer (`InsertTransaction`) to prevent permission bypass.
  - Completed May 22, 2026: `PostingGuard` refined to support system-level bypasses for automated retroactive processing and overrides for `force_closed` dates.
- **Completed Financial Observability**:
  - Completed May 21, 2026: Automated alerts for "Unbalanced Folios" or "Audit Sync Lags."
  - Completed May 21, 2026: Monitoring for excessive usage of closed-date overrides.

**Success Indicator**: Finance teams can identify and resolve ledger discrepancies within minutes of an alert triggering.

---

## 2. Refined Folio Workflows
**Objective**: Handle complex operational edge cases with accuracy and ease.

- **Operational Exceptions**:
  - Completed May 22, 2026: Late Checkout "Approve/Reject" workflow. Triggered by housekeeping status, transitions booking to `review_due_out`. Front desk can explicitly approve (with standard room rate + custom adjustment) or reject the request. Supports direct update of the booking's checkout period within the resolution modal.
  - Completed May 22, 2026: "Early Departure" charge processing and rate correction workflows via `Bookings::ProcessEarlyDeparture`.

**Success Indicator**: Zero manual adjustments required for common guest exceptions (late checkouts, stay extensions).

---

## 3. Reporting Excellence & UX Hardening
**Objective**: Provide actionable insights and a frictionless staff experience.

- **Enterprise Report Package**: 
  - Completed May 22, 2026: "Manager's Flash Report" (Occupancy, ADR, RevPAR, and Daily Revenue) with PDF, Excel, and CSV exports.
  - Completed: "Deposit Liability Report" tracks unearned advance-deposit revenue.
  - Completed May 22, 2026: Multi-page post-close Audit Packet PDF containing daily financial summary, itemized manual adjustments, and audit blockers.
- **UX & Validation Polish**:
  - Completed May 22, 2026: Night audit blocker review views and blocker details endpoint for staff exception review.
  - Completed May 22, 2026: "Force Roll" escape hatch for authorized managers to bypass blockers and prevent operational standstill.

**Success Indicator**: Management can view a complete "Audit Packet" (Daily Summary, Adjustments, Blockers) immediately after the night audit closes via a high-fidelity PDF preview. Audit Packet sections are separated by page for professional archival. If blockers cannot be resolved, an authorized manager can "Force Roll" to advance the business date. Remaining UX polish should deepen guided resolution actions for blocker categories that still require staff interpretation.

---

## 4. Comprehensive Folio & Audit Test Coverage
**Objective**: Cover every folio-and-audit service, model, and controller with meaningful specs. Service coverage is 100% (all 66 services have spec files), but many export specs are shallow (1 example) and some models/controllers are missing.

### 4a. Deepen Export Service Specs (Completed May 22, 2026)
**Current**: All 28 report services have spec files. Deep assertions implemented for core CSV, Excel, and PDF exports to verify financial data accuracy.

- `DepositLiabilityCsvExportService` — **Verified**
- `DepositLiabilityExcelExportService` — **Verified**
- `DepositLiabilityPdfExportService` — **Verified**
- `ManagersFlashCsvExportService` — **Verified**
- `ManagersFlashExcelExportService` — **Verified**
- `ManagersFlashPdfExportService` — **Verified**
- `DailyRevenueCsvExportService` — 1 example
- `DailyRevenueExcelExportService` — 1 example
- `DailyRevenuePdfExportService` — 1 example
- `DailyOccupancyCsvExportService` — 1 example
- `DailyOccupancyExcelExportService` — 1 example
- `DailyOccupancyPdfExportService` — 1 example
- `OutstandingBalanceCsvExportService` — 1 example
- `OutstandingBalanceExcelExportService` — 1 example
- `OutstandingBalancePdfExportService` — 1 example
- `ArrivalsDeparturesCsvExportService` — 1 example
- `ArrivalsDeparturesExcelExportService` — 1 example
- `ArrivalsDeparturesPdfExportService` — 1 example
- `JournalBatchCsvExportService` — 1 example
- `ManagersFlashReport` — 2 examples
- `DailyRevenueReport` — 4 examples
- `DailyOccupancyReport` — 4 examples
- `OutstandingBalanceReport` — 3 examples
- `ArrivalsDeparturesReport` — 5 examples
- `DepositLiabilityReport` — 7 examples
- `FinancialBreakdownExportService` — 3 examples
- `FinancialPerformanceExportService` — 3 examples
- `PayoutsExportService` — 2 examples

**Action**: Each export service should verify at minimum: correct format (CSV headers / sheet names), data correctness (sums match expected), error handling (missing data).

### 4b. Missing Model Specs (Completed May 22, 2026)
- `NightAuditLog` model — **Spec added**
- `PaymentTransaction` model — **Spec added**
- `JournalBatchEntry` model — **Verified**

### 4c. Missing Controller/Request Specs
- `HotelPortal::InventoryAuditLogsController` — request spec covered by `audit_logs_spec.rb`
- `Public::Concierge::ContactController` — **Spec added**

### 4d. Folio Service Depth (Core — Already Good, Add Edge Cases)
All 13 folio services have solid specs (3–12 examples each), but can be strengthened:
- `CloseForCheckout` (11) — add partial-payment and zero-balance edge cases
- `InsertTransaction` (12) — add reversal-id threading edge cases
- `PostStaffTransaction` (10) — add permission-denied scenarios
- `ReverseTransaction` (7) — add already-reversed double-reversal guard

**Success Indicator**: Every folio/audit/report service has >=5 examples covering happy path, validation, and at least one error case. Missing model/controller specs filled. Zero pending stubs.

- **Refund Lifecycle**:
  - Completed foundation: basic refund request lifecycle exists for guest, hotel portal, and admin flows.
  - Completed foundation: admin refund completion records immutable folio refund transactions through `Folios::RecordRefund` with `refund_request_id` metadata.
  - Completed foundation: night audit detects completed refunds that have not been synced to folios as `refund_not_synced` blockers.
  - Remaining: multi-stage refund approval process for high-value transactions.
  - Remaining: direct linking of refund ledger entries to original payment gateway IDs for easier staff-facing tracing.
  - Remaining: decide whether refund completion should execute automated gateway refunds or stay as an administrative/manual settlement confirmation.
