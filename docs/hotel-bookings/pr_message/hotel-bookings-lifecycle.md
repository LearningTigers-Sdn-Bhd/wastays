# PR: Hotel Booking Lifecycle Foundation

## Background

WAStays needs explicit and auditable reservation transitions that coordinate inventory, guest stays, folio state, and nightly operations.

## Solution

- Added a booking status lifecycle and transition services.
- Connected check-in and checkout to folio initialization and settlement.
- Added missed-arrival review, no-show finalization, early departure, room assignment, and inventory coordination.

## Domain Boundaries

- Hotel bookings owns reservation and stay-state decisions.
- Folio transactions owns financial consequences of those decisions.
- Night audits owns business-date close and scheduled no-show processing.

## Verification

Use standard and exception lifecycle integration specs plus booking service and request specs.
