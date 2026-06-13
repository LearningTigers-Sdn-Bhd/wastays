# Hotel Bookings Foundation

## Completed
- Added an explicit booking status lifecycle instead of ad hoc status changes.
- Connected check-in to folio initialization and captured-payment synchronization.
- Connected checkout to earned-charge validation, settlement, folio closure, and invoice generation.
- Added missed-arrival review and no-show finalization.
- Added room assignment, inventory coordination, audit logging, and lifecycle webhooks.
- Added early-departure processing and stay-update coordination.

## Cross-Domain Contracts
- Folio transactions owns financial initialization, forecasts, settlement, and closure.
- Night audits processes unresolved no-shows and supplies business-date governance.
