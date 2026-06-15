# PR: Folio Transactions Foundation

## Background

WAStays needs an immutable guest ledger that remains accurate across payment capture, daily charging, operational corrections, refunds, and checkout.

## Solution

- Added booking folios and append-only folio transactions.
- Centralized transaction insertion, category validation, permission enforcement, and posting-date controls.
- Added nightly charge posting, forecasted charges, payment synchronization, refunds, reversals, and checkout settlement.
- Added ledger-based invoices, receipts, and exports.

## Domain Boundaries

- Hotel bookings owns reservation state, check-in, checkout, early departure, and no-show decisions.
- Night audits owns business-date closing, audit events, General Ledger batches, and daily reconciliation.
- Folio transactions owns the guest ledger and all money-movement entries posted to it.

## Verification

Use model, service, request, integration, and lifecycle specs covering `BookingFolio`, `FolioTransaction`, and the `Folios` service namespace.
