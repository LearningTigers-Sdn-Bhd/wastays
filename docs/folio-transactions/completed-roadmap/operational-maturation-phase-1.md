# Folio Transactions Operational Maturation - Phase 1

## Completed
- Replaced `post_folio_transactions` with permissions for charges, payments, refunds, adjustments, corrections, and write-offs.
- Enforced granular permissions inside `Folios::InsertTransaction` so non-controller entry points cannot bypass authorization.
- Added controlled posting into locked dates through `override_financial_date_lock` and mandatory reasons.
- Implemented the basic refund request-to-ledger lifecycle with `refund_request_id` traceability.
- Corrected reversal behavior for negative payment transactions.
- Hardened booking financial column precision to prevent rounding errors.
- Added forecasted room and tax charges, retry-safe synchronization, and reversal reconciliation.
- Fixed early-departure projected checkout balance double counting.
