# Night Audits Changelog

## May 22, 2026 - Operational Resilience and Reporting (Current)

### Changes
- Added authorized force roll with immutable `business_date_force_closed` audit events.
- Added the multi-page Audit Packet with financial summary, adjustments, and blockers.
- Expanded daily revenue and Manager's Flash reporting to include all charge categories.
- Standardized audit summaries and General Ledger selection on `posting_date`.

---

## May 21, 2026 - Accounting and Observability Hardening

### Changes
- Classified no-show accounting from folio transaction category.
- Added alerts for unbalanced folios, audit synchronization lag, and excessive closed-date overrides.

---

## May 20, 2026 - Night Audit Foundation

### Changes
- Added business-date governance, blocker evaluation, nightly orchestration, atomic day roll, financial summaries, and journal batches.
- Made journal creation fail when business-day transactions lack General Ledger Codes.
- Protected daily revenue reporting with `view_reports`.
