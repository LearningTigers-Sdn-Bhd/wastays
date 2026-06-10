# Folio: Checkout Settlement

## Status

Completed foundation.

## Purpose

Prevents guest departure from closing financially until all earned charges are posted and the folio is settled.

## Key Files

- `app/services/folios/close_for_checkout.rb`
- `app/services/folios/sync_forecasted_charges.rb`
- `app/services/bookings/transition_status.rb`
- `app/services/folio_invoice_pdf_service.rb`
- `app/models/booking_folio.rb` — `unsettled_forecasts`, `projected_forecasts`, `all_charges_posted?` helpers
- `app/controllers/hotel_portal/bookings_controller.rb`
- `app/views/hotel_portal/bookings/folio.html.erb`

## Rules Made So Far

- Checkout closure is blocked for positive balances.
- Credit balances must be resolved before closure.
- Checkout runs `SyncForecastedCharges` before missing-charge validation so existing open folios without forecast rows cannot bypass validation.
- Missing nightly charges block checkout (detected via unsettled forecast records for stay dates before the current checkout date).
- Closed folios can produce itemized invoice or receipt output.

## Known Follow-Ups

- Improve user guidance around why checkout is blocked and what action resolves it.
- Include audit-packet links once current-progress reporting is complete.
