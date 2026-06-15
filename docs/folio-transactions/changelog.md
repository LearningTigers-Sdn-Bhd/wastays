# Folio Transactions Changelog

## June 11, 2026 - Forecast Lifecycle Hardening (Current)

### Changes
- Centralized forecast-line construction and charge posting keys.
- Made forecast generation retry-safe.
- Superseded linked forecasts when actualized nightly charges are reversed so checkout detects missing charges again.

### Verification
- Folio forecast generation, synchronization, reversal, and checkout specs cover the hardened lifecycle.

---

## June 10, 2026 - Forecasted Charges

### Changes
- Added pending forecast rows for expected room and tax charges.
- Reconciled forecasts after booking changes, catch-up posting, early departure, and checkout.
- Fixed early-departure projected-balance double counting.

---

## May 22, 2026 - Ledger Governance

### Changes
- Enforced granular folio permissions at the transaction service boundary.
- Allowed controlled closed-date overrides and system posting bypasses.
- Corrected refund reversal handling and standardized financial selection on `posting_date`.

---

## May 20, 2026 - Folio Foundation

### Changes
- Established immutable folio transactions, explicit reversals, nightly room and tax charges, and checkout settlement gates.
- Replaced the broad folio-posting permission with action-specific permissions.
