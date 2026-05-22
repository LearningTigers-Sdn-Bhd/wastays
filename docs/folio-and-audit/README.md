# Folio And Audit Documentation

This folder contains the operational documentation for booking lifecycle, folios, financial controls, night audit, and reporting.

## Structure

- `completed-roadmaps/` - Roadmaps and milestones that are treated as completed implementation records.
- `current-progress-roadmaps/` - Current in-progress roadmap items and readiness gaps.
- `knowledges/` - Feature-level knowledge records for what has been built so far.
- `planning/` - Forward-looking enterprise planning documents.
- `reference/` - Domain references and target operating models.

## Reading Order

1. Start with `reference/night-audit-reference.md` for the target PMS operating model.
2. Review `completed-roadmaps/foundation.md` for the implemented foundation.
3. Review `completed-roadmaps/operational-maturation-phase-1.md` for completed maturation work.
4. Review `current-progress-roadmaps/operational-maturation.md` for remaining current priorities.
5. Use `knowledges/` for implementation-level feature details.

## Readiness Note

The foundation is substantially implemented. Full operational readiness still depends on closing the items in `current-progress-roadmaps/`, specifically the blocker dashboard UX, as refund approval workflows have been deferred to a subsequent phase.

Recent financial hardening completed on May 20, 2026: `daily_revenue` report access is covered by `view_reports`, and journal batch creation now fails fast when business-day folio transactions are missing GL codes instead of silently omitting them.

Recent no-show accounting hardening completed on May 21, 2026: no-show room charges now post as `no_show_charge`, no-show tax remains `tax`, and GL/report classification uses folio transaction category rather than metadata as the accounting source of truth.

Recent operational maturation completed on May 22, 2026: Manager Flash Report implemented with optimized custom SQL for occupancy, ADR, RevPAR, and revenue. Early Departure workflows (truncation and charge processing) are fully functional.

Recent reporting excellence completed on May 22, 2026: Multi-page Audit Packet implemented as a high-fidelity PDF preview, aggregating the daily financial summary, manual adjustments, and audit blockers into a single uneditable artifact. `adjustments_total` added to financial summaries for explicit staff-intervention tracking.
