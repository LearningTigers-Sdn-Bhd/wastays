# Core Foundation (Completed)

This document serves as the official record of the financial and night audit foundation. These features have been implemented, tested, and verified as production-ready.

## 1. Architectural Principles
To ensure enterprise-grade reliability, the financial system was built on three core pillars:
- **Immutability**: Folio transactions are never edited or deleted. Corrections are handled via explicit reversals and new postings.
- **State-Driven Controls**: Financial activity is governed by the `HotelBusinessDate` state machine, preventing accidental postings into closed or running audit periods.
- **Atomic Auditing**: Every money-impacting action automatically generates a corresponding entry in the immutable `FinancialAuditEvent` ledger.

## 2. Booking & Folio Transaction Engine
The system handles the full lifecycle of guest financial transactions:
- **Booking Payments**: Securely syncs booking-time payments into guest folios upon check-in, ensuring accurate opening balances while keeping security deposits separate.
- **Granular Folio Actions**: Empowers staff to post charges (Room, Tax, F&B, Other), record payments, issue refunds, and apply adjustments with strict category validation.
- **Automated Nightly Charges**: The Night Audit engine automatically posts daily room revenue and taxes, moving away from "full-stay" upfront charging.
- **Checkout Settlement Gates**: Prevents departures until the folio is balanced, settled, and officially closed.
- **Professional Invoicing**: Generates itemized, ledger-based PDF invoices and receipts via the `FolioInvoicePdfService`.

## 3. Business Date & Night Audit Governance
The `HotelBusinessDate` model acts as the financial pulse of the property:
- **Explicit States**: Tracks the business day through `open`, `audit_running`, `audit_blocked`, and `closed` states.
- **Audit Orchestration**: The `RunNightAudit` service manages the transition between dates, executing no-show processing and nightly postings while holding row-level locks to prevent duplicate runs.
- **Explicit Day Roll**: A successful night audit atomically closes the audited `HotelBusinessDate` and opens or reuses the next `HotelBusinessDate` in `open` state. Blocked or failed audits do not advance the business date.
- **Race-Safe Date Claims**: Business-date creation and next-date opening are protected against duplicate-row races and locked before state is trusted, preventing concurrent audit attempts from reopening or corrupting date state.
- **Blocker Resolution**: A sophisticated evaluation engine detects operational "blockers" (e.g., unclosed folios, unsynced payments) that must be resolved before a date can be closed.

## 4. Financial Controls & Security
- **PostingGuard Enforcement**: A centralized gateway that validates every transaction against the current business date state and actor permissions.
- **Authorized Overrides**: Supports controlled "back-posting" into closed dates, requiring specific permissions (`override_financial_date_lock`) and a mandatory audit reason.
- **Immutable Audit Ledger**: The `FinancialAuditEvent` system captures a permanent trail of all successful financial movements and audit state changes, copying request IDs for end-to-end traceability.
- **Business-Date Audit Events**: Night audit records `night_audit_completed`, `business_date_closed`, and `business_date_opened` as part of the successful close/open transaction so date transitions are reconstructable from the audit ledger.
