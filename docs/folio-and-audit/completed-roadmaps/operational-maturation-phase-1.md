# Completed: Operational Maturation (Phase 1)

This document records the completed milestones from the Operational Maturation roadmap. These features provide the robust accounting foundation and financial visibility required for reliable daily operations.

---

## 1. Accounting Foundation & Governance
**Status**: Completed May 20, 2026

- **General Ledger (GL) Mappings**: 
  - Implemented automated mapping for all transaction categories (Accommodation, Tax, F&B, No-Show, etc.).
  - Added management UI for hotel-specific GL code configuration.
- **Journal Batching**: 
  - Automated creation of Journal Batches during the Night Audit process.
  - Implemented CSV export for streamlined reconciliation with external accounting software.

---

## 2. Revenue Tracking & Reporting
**Status**: Completed May 20, 2026

- **Granular Tax Tracking**: 
  - Precision tracking of individual tax components (VAT, City Tax, Tourism Levies).
  - Each component is recorded as a distinct line item on the folio for accurate remittance reporting.
- **Daily Revenue Reporting**:
  - Implementation of `DailyRevenueReport` with support for PDF, CSV, and Excel exports.
  - Revenue is broken down by category and department as specified.

---

## 3. Audit Visibility
**Status**: Completed May 20, 2026

- **Financial Audit Logs**:
  - Centralized audit trail for all financial events.
  - Improved visibility for staff to track "who posted what and when" within the hotel portal.

---

## 4. Business Date Day-Roll Hardening
**Status**: Completed May 20, 2026

- **Explicit Next-Date Opening**:
  - Successful night audit now closes the audited business date and opens the next `HotelBusinessDate` in the same completion transaction.
  - Blocked and failed audits do not open the next business date.
- **Audit-Ledger Coverage**:
  - Added `business_date_opened` financial audit events.
  - Completion, close, and open audit events are persisted atomically with the date transition.
- **Concurrency Safety**:
  - Business-date creation and next-date opening reuse existing rows when safe.
  - Existing locked next dates cause a safe audit failure instead of being overwritten.
