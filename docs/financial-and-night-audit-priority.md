# Financial And Night Audit Priority

This document groups the recommended financial and night audit enterprise-readiness work by priority.

## High Priority

### 1. Business Date And Night Audit Hardening

Adds durable property business dates, closed-date locks, row-level night audit locking, retry/reopen/force-close workflows, and manager sign-off.

This should come first because all financial posting, reporting, and period control depends on reliable business-date governance.

### 2. Financial Reporting Unification

Standardizes revenue, payments, tax, balances, and occupancy-related financial metrics around folio postings and business dates.

This is high priority because enterprise users will lose trust if financial performance, daily revenue, folio ledger, and night audit summaries do not reconcile.

### 3. Financial Audit And Control Logging

Creates immutable audit logging for charges, payments, refunds, reversals, adjustments, closed-date overrides, and night audit actions.

This is high priority because enterprise financial operations require accountability for every money-impacting change.

## Medium Priority

### 4. Accounting Foundation

Adds configurable GL mappings, journal batches, export statuses, accounting period locks, and reconciliation reports.

This is medium priority because the PMS can operate before full accounting integration, but enterprise finance teams will eventually require this.

### 5. Financial Permission Segregation

Splits broad financial permissions into specific controls for posting charges, refunds, reversals, write-offs, closed-date postings, force-close, reopen, and accounting exports.

This is medium priority because it becomes critical as more staff roles use the system, especially for fraud prevention and approval workflows.

### 6. Enterprise Financial Reports Package

Adds manager report, night audit packet, tax report, tender report, deposit liability, cancellation/no-show, adjustment/void, refund, checkout exception, and open folio reports.

This is medium priority because some reporting exists already, but enterprise operators need a broader, reconciled reporting package.

## Low Priority

### 7. Financial And Night Audit Observability

Adds metrics and alerts for failed audits, blocked audits, duplicate posting prevention, payment/refund sync lag, unbalanced folios, closed-date override usage, accounting export failures, long-running reports, and revenue/payment mismatches.

This is lower priority than correctness and controls, but important once the financial foundation is stable and the system is used at scale.
