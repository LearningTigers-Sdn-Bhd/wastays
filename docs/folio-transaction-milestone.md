# Folio Transaction Milestones

## Completed

### Milestone 1: Advance Deposits
- Add `advance_deposit` folio payment category.
- Sync captured booking quote payments into folios as advance deposits.
- Ensure existing payment sync is locked and idempotent.

### Milestone 2: Nightly Charge Posting
- Add nightly room and tax posting through night audit.
- Stop posting the full stay charge at check-in.
- Add idempotency protection for nightly charges.
- Keep checkout day uncharged.

### Milestone 3: Checkout Settlement
- Add checkout folio settlement gate.
- Block checkout when folio has outstanding charges, credit balance, missing folio, or closed folio.
- Close settled folios during checkout.
- Add checkout confirmation UI.

### Milestone 4: Staff Folio Actions
- Add staff-posted folio transactions.
- Add `post_folio_transactions` permission.
- Support cash payments, refunds, other charges, adjustments, discounts, write-offs, corrections, and other adjustments.
- Restrict manual charges to `other` only.
- Store refunds as negative payment entries.
- Add folio action modals to booking show page.

### Milestone 5: Night Audit Reconciliation & Reports
- Add pre-audit blockers dashboard.
- Show pending arrivals, due departures, unsettled folios, and audit exceptions.
- Add night audit run summary with room revenue, tax, payments, refunds, no-show penalties, and occupancy totals.
- Add folio balance exception report for positive and credit balances.
- Link audit results to affected bookings and folios.
- Support retroactive financial summary recalculation with audit trail.

### Manual Payment Capture (Manual Bookings)
- Add optional payment recording for manual bookings.
- Support cash, credit card, and bank transfer manual entries.
- Automatically sync manual payments as advance deposits upon check-in.
- Default manual booking payment status to `pending`.

## Remaining

### Milestone 6: Guest Invoice and Receipt Generation
- Generate itemized invoice from closed folio.
- Include charges, taxes, payments, refunds, discounts, write-offs, and adjustments.
- Add receipt or invoice numbering.
- Add PDF/download support.
- Ensure invoice totals match folio balance.

### Milestone 7: Tax and Revenue Breakdown
- Split room revenue, tax, fees, refunds, discounts, and write-offs in reports.
- Track tax components separately where needed.
- Add exportable daily revenue report.
- Prepare transaction categories for accounting reconciliation.

### Milestone 8: Operational Exceptions
- Handle early checkout.
- Add late checkout fee workflow.
- Add rate correction workflow using adjustments instead of deleting posted charges.
- Support stay extensions and overstay handling.
- Block checkout when required operational conditions remain unresolved.

### Milestone 9: Refund and Credit Workflow
- Add formal refund workflow for credit folios.
- Track refund status and approval state if required.
- Link refund ledger entries to refund records.
- Support partial refunds.

### Milestone 10: Folio Split and Transfer
- Support moving folio line items between folios.
- Support guest, company, and OTA folio separation if needed.
- Support partial guest/company payment allocation.
- Preserve audit trail for every transfer.

### Milestone 11: Accounting Export
- Export daily ledger and revenue data.
- Map folio transaction categories to accounting codes.
- Add CSV/XLS exports.
- Reconcile gateway, cash, refund, and write-off totals.

### Milestone 12: Hardening and UX Polish
- Add full system specs for check-in, night audit, checkout, refund, and folio action flows.
- Harden permission edge cases.
- Improve inline validation and modal error handling.
- Improve audit log visibility.
- Run final focused specs, broad specs, and RuboCop cleanup.

## Recommended Next Milestone

Milestone 6: Guest Invoice and Receipt Generation.
