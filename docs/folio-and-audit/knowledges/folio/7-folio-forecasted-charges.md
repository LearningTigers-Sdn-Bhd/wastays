# Folio: Forecasted Charges

## Status

Completed June 10, 2026. Forecast lifecycle hardening completed June 11, 2026.

## Purpose

Pre-computes expected nightly room and tax charges at check-in and displays them as pending forecast rows on the folio page. During night audit, each posted charge actualizes its matching forecast. If a booking's dates, rooms, rates, catch-up state, or early-departure state changes, forecasts are reconciled through `Folios::SyncForecastedCharges` so stale pending rows are superseded without recreating already-posted nights.

Forecasts are a separate model (`FolioForecastedCharge`) — they do not affect folio balance or financial reports. Only real `FolioTransaction` entries count toward the ledger.

## Key Files

- `app/models/folio_forecasted_charge.rb`
- `app/models/booking_folio.rb` — `unsettled_forecasts`, `projected_forecasts`, `all_charges_posted?` helpers
- `app/services/folios/forecasted_charge_lines.rb` — shared expected-line builder for forecast generation and sync
- `app/services/folios/charge_posting_keys.rb` — shared idempotency key formats for nightly, catch-up, early-checkout, and no-show postings
- `app/services/folios/generate_forecasted_charges.rb`
- `app/services/folios/sync_forecasted_charges.rb` — reconciles active forecasts after lifecycle changes and before checkout validation
- `app/services/folios/post_nightly_charges.rb` — actualizes forecasts after successful insert or idempotent retry
- `app/services/folios/reverse_transaction.rb` — supersedes actualized forecasts when the matching nightly charge is reversed
- `app/services/folios/initialize_for_booking.rb` — triggers forecast generation at check-in
- `app/services/folios/process_catch_up_charges.rb` — posts catch-up charges and syncs forecasts on reinstate
- `app/services/folios/close_for_checkout.rb` — syncs forecasts, then validates unsettled forecasts before checkout
- `app/services/bookings/update_stay_service.rb` — syncs forecasts on date/room/rate changes
- `app/services/bookings/process_early_departure.rb` — syncs forecasts after checkout truncation
- `app/services/bookings/finalize_no_show.rb` — supersedes normal stay forecasts after no-show posting
- `app/views/hotel_portal/bookings/folio.html.erb` — passes projections to partials
- `app/views/hotel_portal/bookings/folio/_folio_transaction_table.html.erb` — renders amber "Pending / Forecast" rows
- `spec/models/folio_forecasted_charge_spec.rb`
- `spec/services/folios/generate_forecasted_charges_spec.rb`
- `spec/services/folios/sync_forecasted_charges_spec.rb`
- `spec/integration/lifecycles/exception_booking_lifecycle_spec.rb` — early departure, reinstate scenarios
- `spec/integration/lifecycles/standard_booking_lifecycle_spec.rb` — standard audit cycles

## Data Model

```ruby
# schema: folio_forecasted_charges
#   booking_folio_id   (FK)
#   stay_date           (date, NOT NULL)
#   charge_kind         (string: "accommodation" | "tax")
#   identity            (string: booking_room_id or tax_line_identity)
#   amount              (decimal)
#   description         (string)
#   status              (string: "forecast" | "actualized" | "superseded")
#   metadata            (jsonb)
#   actualizing_transaction_id (FK -> folio_transactions, nullable)
```

## Lifecycle

```
 CHECK-IN                    NIGHT AUDIT                  LIFECYCLE CHANGE
    |                            |                             |
 Folio opens           PostNightlyCharges runs        Dates/rooms/rates,
 InitializeForBooking  creates FolioTransaction       catch-up, reinstate,
 generates forecasts   + actualizes matching          early departure
 (status: forecast)      forecast (→ actualized)      → SyncForecastedCharges
                         retry actualizes existing    → stale rows superseded
                         charge forecasts             → unposted rows retained
```

## Rules

- Forecasts are created at check-in by `GenerateForecastedCharges`, which uses `ForecastedChargeLines`. `SyncForecastedCharges` uses the same builder, so generation and reconciliation share one source of truth for expected accommodation/tax rows.
- `ForecastedChargeLines` reuses the same `NightlyChargeCalculation` concern as `PostNightlyCharges`, ensuring forecast amounts match what the audit will post.
- `GenerateForecastedCharges` is retry-safe: it skips existing active/actualized forecasts and already-posted nightly/catch-up lines, with the partial unique index remaining as the final concurrency guard.
- Each forecast has a partial unique index on `(folio_id, charge_kind, identity, stay_date) WHERE status = 'forecast'`, preventing duplicate forecasts for the same night/charge.
- Posting idempotency keys are built by `ChargePostingKeys` so nightly, catch-up, early-checkout, and no-show paths do not drift in key format.
- During night audit, `PostNightlyCharges` calls `actualize_forecast!` after each successful `InsertTransaction`, linking the forecast to the real transaction via `actualizing_transaction_id`.
- If night audit is retried after a transaction was inserted but before the forecast was actualized, `PostNightlyCharges` finds the existing transaction by `nightly_charge_key` and actualizes the matching forecast.
- Booking mutations (dates, room type, rate plan), catch-up processing, and early departure call `SyncForecastedCharges`. The sync service computes expected lines, supersedes stale pending rows, skips already actualized rows, and does not create pending forecasts for nights already posted by non-voided night audit or catch-up keys.
- Reversing an actualized nightly charge supersedes the linked forecast and runs `SyncForecastedCharges`. If the booking/folio still requires the night, sync creates a new pending forecast; terminal bookings and closed folios do not get recreated active forecasts.
- No-show processing supersedes normal stay forecasts after no-show charges are posted because the reservation is no longer expected to follow the standard occupied-night forecast lifecycle.
- Checkout settlement (`CloseForCheckout`) runs `SyncForecastedCharges`, then uses `booking_folio.unsettled_forecasts.where(stay_date: ...< checkout)` to detect missing nightly charges only for dates before the current checkout date.
- Projected UI rows use `BookingFolio#projected_forecasts`, which excludes closed folios, terminal booking states (`cancelled`, `completed`, `no_show`), and forecasts on or after the current checkout date.
- Forecast rows are displayed on the folio page as amber-highlighted "Pending / Forecast" entries, visually distinct from posted transactions. The outstanding balance banner includes projected amounts in `total_charges`.
- Charges posted through non-audit paths such as early-departure charge processing do not directly actualize standard nightly forecasts; related lifecycle services sync or supersede forecasts so projections remain accurate.
- The checkout sheet's "Resolve Balance" card uses `projected_outstanding_balance` (which includes unsettled forecasts) as its baseline. For early departures, this creates a double-counting risk because both the regular forecasts and the early departure charges cover the same unused nights. The method `Folios::PostEarlyCheckoutCharges.projected_checkout_balance` resolves this by computing `outstanding_balance + pending_early_departure_charges`, skipping the overlapping forecasts entirely.

## Verification

- `bundle exec rspec spec/services/folios/charge_posting_keys_spec.rb spec/services/folios/generate_forecasted_charges_spec.rb spec/services/folios/sync_forecasted_charges_spec.rb spec/services/folios/post_nightly_charges_spec.rb spec/services/folios/post_early_checkout_charges_spec.rb spec/services/folios/reverse_transaction_spec.rb spec/services/bookings/finalize_no_show_spec.rb`
- `bundle exec rspec spec/integration/lifecycles/standard_booking_lifecycle_spec.rb spec/integration/lifecycles/exception_booking_lifecycle_spec.rb` — 11 examples, 0 failures.

## Known Follow-Ups

- Extend forecast generation to handle package postings (breakfast, parking) if rate plans include them.
- Add hotel-level toggle for forecast visibility on the folio page if required by property operations.
