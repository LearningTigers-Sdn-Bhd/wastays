# Booking Lifecycle: Check-In And Check-Out

## Status

Mostly completed foundation.

## Purpose

Connects stay transitions to folio opening, nightly charge validation, balance settlement, and folio closure.

## Key Files

- `app/services/bookings/transition_status.rb`
- `app/services/bookings/update_stay_service.rb`
- `app/services/folios/initialize_for_booking.rb`
- `app/services/folios/close_for_checkout.rb`
- `app/views/hotel_portal/bookings/folio.html.erb`
- `spec/integration/lifecycles/standard_booking_lifecycle_spec.rb`

## Rules Made So Far

- Check-in initializes the guest folio when needed.
- Existing captured booking payments are synchronized into the folio as booking payments.
- Optional collected security deposits can be recorded at check-in and are tracked separately from folio payments.
- Checkout is blocked unless required nightly charges have been posted and the folio balance is settled.
- Folio closure records an auditable financial event.

## Known Follow-Ups

- Add richer staff guidance for blocked checkout scenarios.
- Extend early departure handling to account for policy-driven penalties and refunds.
