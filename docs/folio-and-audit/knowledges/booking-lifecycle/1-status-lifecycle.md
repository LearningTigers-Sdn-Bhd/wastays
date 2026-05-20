# Booking Lifecycle: Status Lifecycle

## Status

Completed foundation, with remaining operational exception workflows tracked in current progress roadmaps.

## Purpose

Controls reservation state changes so bookings move through explicit PMS states instead of ad hoc status updates.

## Key Files

- `app/models/booking.rb`
- `app/models/concerns/bookings/status_lifecycle.rb`
- `app/services/bookings/transition_status.rb`
- `app/controllers/hotel_portal/bookings_controller.rb`
- `spec/integration/lifecycles/standard_booking_lifecycle_spec.rb`
- `spec/integration/lifecycles/exception_booking_lifecycle_spec.rb`

## Rules Made So Far

- Bookings use explicit statuses such as `pending`, `confirmed`, `checked_in`, `cancelled`, `completed`, `overbooked`, and `no_show`.
- Status changes are constrained through lifecycle rules instead of free-form updates.
- Lifecycle services centralize changes that have side effects, such as check-in, checkout, cancellation, reinstatement, and no-show processing.

## Known Follow-Ups

- Expand operational exception workflows for late checkout, early departure penalties, and rate corrections.
- Keep lifecycle changes tied to financial posting rules when a transition affects folio balances.
