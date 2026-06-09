# Folio And Audit Documentation

This folder contains the operational documentation for booking lifecycle, folios, financial controls, night audit, and reporting.

## Structure

- `completed-roadmaps/` - Roadmaps and milestones that are treated as completed implementation records.
- `current-progress-roadmaps/` - Current in-progress roadmap items and readiness gaps.
- `knowledges/` - Feature-level knowledge records for what has been built so far.
- `planning/` - Forward-looking enterprise planning documents.
- `reference/` - Domain references and target operating models.

## Reading Order

1. Start with `reference/night-audit-reference.md` for the target Property Management System (PMS) operating model.
2. Review `completed-roadmaps/foundation.md` for the implemented foundation.
3. Review `completed-roadmaps/operational-maturation-phase-1.md` for completed maturation work.
4. Review `current-progress-roadmaps/operational-maturation.md` for remaining current priorities.
5. Use `knowledges/` for implementation-level feature details.

## Readiness Note

The foundation is substantially implemented. Full operational readiness still depends on closing the items in `current-progress-roadmaps/`, specifically deeper guided blocker resolution and enterprise refund approval/reconciliation workflows. The basic refund request-to-ledger lifecycle is implemented.

Recent financial hardening completed on May 20, 2026: `daily_revenue` report access is covered by `view_reports`, and journal batch creation now fails fast when business-day folio transactions are missing General Ledger Codes (GL Codes) instead of silently omitting them.

Recent no-show accounting hardening completed on May 21, 2026: no-show room charges now post as `no_show_charge`, no-show tax remains `tax`, and General Ledger (GL)/report classification uses folio transaction category rather than metadata as the accounting source of truth.

Recent operational maturation completed on May 22, 2026: Manager Flash Report implemented with optimized custom SQL for occupancy, Average Daily Rate (ADR), Revenue per Available Room (RevPAR), and revenue. Early Departure workflows (truncation and charge processing) are fully functional.

Recent reporting excellence completed on May 22, 2026: Multi-page Audit Packet implemented as a high-fidelity PDF preview, aggregating the daily financial summary, manual adjustments, and audit blockers into a single uneditable artifact. `adjustments_total` added to financial summaries for explicit staff-intervention tracking.

Recent operational resilience completed on May 22, 2026: "Force Roll" capability implemented to prevent operational standstills. Authorized managers can now bypass night audit blockers to advance the business date, with all bypasses recorded as `force_closed` states in the audit ledger and a new `business_date_force_closed` financial audit event.

Recent financial hardening completed on May 22, 2026: Refund reversal logic fixed to correctly handle negative payments; financial selection logic harmonized across Audit Summary and General Ledger to use `posting_date` exclusively; database precision hardened for booking financial columns to prevent rounding errors.

Recent financial governance hardening completed on May 22, 2026: Granular folio permissions (charges, payments, adjustments, corrections) are now enforced at the service layer (`InsertTransaction`) instead of just the controller, preventing unauthorized activity from any entry point.

Recent reporting consistency completed on May 22, 2026: `DailyRevenueReport` and `ManagersFlashReport` expanded to include all charge categories (Food and Beverage (F&B), No-Show, Late Checkout, etc.) in a new `other_revenue` column, ensuring total revenue reflects the entire ledger.

Recent operational resilience completed on May 22, 2026: `PostingGuard` refined to allow authorized overrides on `force_closed` dates and support system-level bypasses for automated background tasks (syncs, automated check-ins) targeting closed dates.

Recent refund lifecycle documentation updated on June 9, 2026: the implemented basic refund request flow is now recorded separately from deferred enterprise refund work. Guests or staff can submit refund requests, admins can approve/reject/complete them, and completed refunds are posted to folios through `Folios::RecordRefund` with `refund_request_id` traceability.
