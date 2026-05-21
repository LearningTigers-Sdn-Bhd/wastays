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
- **Financial Observability**: 
  - Automated alerts for "Unbalanced Folios" or "Audit Sync Lags."
  - Monitoring for excessive usage of closed-date overrides.

**Success Indicator**: Finance teams can identify and resolve ledger discrepancies within minutes of an alert triggering.

---

## 2. Refined Folio Workflows
**Objective**: Handle complex operational edge cases with accuracy and ease.

- **Operational Exceptions**:
  - Completed May 21, 2026: Late Checkout "Alert Only" workflow. Triggered by housekeeping status, transitions booking to `review_due_out`. Front desk can then manually apply a penalty (calculated from current room rates + taxes) or waive it.
  - "Early Departure" penalty processing and rate correction workflows.
- **Refund Lifecycle**:
  - Multi-stage refund approval process for high-value transactions.
  - Direct linking of ledger entries to original payment gateway IDs for easier tracing.

**Success Indicator**: Zero manual adjustments required for common guest exceptions (late checkouts, stay extensions).

---

## 3. Reporting Excellence & UX Hardening
**Objective**: Provide actionable insights and a frictionless staff experience.

- **Enterprise Report Package**: 
  - "Manager's Flash Report" (Occupancy, ADR, RevPAR, and Daily Revenue).
  - Completed: "Deposit Liability Report" tracks unearned advance-deposit revenue.
  - Complete post-close audit packet containing daily summary, exceptions, and adjustments.
- **UX & Validation Polish**:
  - Real-time "Blocker Dashboard" that guides staff through resolving night audit exceptions.

**Success Indicator**: Management can view a complete "Audit Packet" (Daily Summary, Exceptions, Adjustments) immediately after the night audit closes.
