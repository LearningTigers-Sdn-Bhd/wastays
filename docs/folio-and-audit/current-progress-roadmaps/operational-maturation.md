# Active Roadmap: Operational Maturation

This roadmap outlines the remaining priorities required to transition from a functional foundation to a high-performance, operationally mature financial system.

---

## 1. Advanced Financial Controls & Governance
**Objective**: Introduce professional-grade financial oversight and fraud prevention.

- **Permission Segregation**: 
  - Moving away from broad "Financial" access to granular controls (e.g., separate permissions for "Post Write-Off", "Execute Refund", and "Date Override").
- **Financial Observability**: 
  - Automated alerts for "Unbalanced Folios" or "Audit Sync Lags."
  - Monitoring for excessive usage of closed-date overrides.

**Success Indicator**: Finance teams can identify and resolve ledger discrepancies within minutes of an alert triggering.

---

## 2. Refined Folio Workflows
**Objective**: Handle complex operational edge cases with accuracy and ease.

- **Operational Exceptions**:
  - Automated "Late Checkout Fee" workflows triggered by housekeeping status.
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
  - "Deposit Liability Report" to track unearned revenue.
- **UX & Validation Polish**:
  - Real-time "Blocker Dashboard" that guides staff through resolving night audit exceptions.

**Success Indicator**: Management can view a complete "Audit Packet" (Daily Summary, Exceptions, Adjustments) immediately after the night audit closes.
