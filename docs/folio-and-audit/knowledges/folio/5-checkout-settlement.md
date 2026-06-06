# Folio: Checkout Settlement

## Status

Completed foundation.

## Purpose

Prevents guest departure from closing financially until all earned charges are posted and the folio is settled.

## Key Files

- `app/services/folios/close_for_checkout.rb`
- `app/services/bookings/transition_status.rb`
- `app/services/folio_invoice_pdf_service.rb`
- `app/controllers/hotel_portal/bookings_controller.rb`
- `app/views/hotel_portal/bookings/folio.html.erb`

## Rules Made So Far

- Checkout closure is blocked for positive balances.
- Credit balances must be resolved before closure.
- Missing nightly charges block checkout.
- Closed folios can produce itemized invoice or receipt output.

## Known Follow-Ups

- Improve user guidance around why checkout is blocked and what action resolves it.
- Include audit-packet links once current-progress reporting is complete.
