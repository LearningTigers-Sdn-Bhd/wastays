# Folio Transactions Foundation

## Completed
- Created one guest financial ledger per booking through `BookingFolio`.
- Made posted `FolioTransaction` records append-only; corrections use explicit reversal or adjustment entries.
- Added a centralized insertion gateway for category validation, posting-date controls, permissions, and audit-event creation.
- Synced captured booking payments into folios while keeping security deposits separate.
- Posted room revenue and taxes nightly instead of charging the full stay upfront.
- Prevented checkout until earned charges are posted, the balance is settled, and the folio can close.
- Generated itemized, ledger-based folio invoices and receipts.

## Cross-Domain Contracts
- Hotel booking check-in initializes the folio; checkout requests folio settlement and closure.
- Night audit actualizes nightly forecasts and posts room and tax transactions.
- Night audit owns business-date state, financial audit events, and General Ledger reconciliation.
