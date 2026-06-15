# Night Audits Foundation

## Completed
- Established `HotelBusinessDate` as the property's financial clock with explicit open, running, blocked, closed, and force-closed states.
- Added blocker evaluation for operational and financial conditions that prevent close.
- Added race-safe night-audit orchestration that posts earned charges, processes no-shows, persists summaries, closes the date, and opens the next date atomically.
- Ensured blocked and failed runs do not advance the business date.
- Recorded immutable audit events for completion and business-date transitions.
- Added financial summaries, General Ledger journal batches, and operational reports.

## Cross-Domain Contracts
- Folio transactions supplies the immutable ledger and nightly posting services.
- Hotel bookings supplies occupancy, arrival, departure, and no-show state.
