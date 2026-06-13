# Hotel Bookings Changelog

## June 10, 2026 - Early Departure Settlement Hardening (Current)

### Changes
- Fixed projected checkout balance double counting for prepaid early departures.
- Kept booking date and room changes synchronized with folio forecasts.

---

## May 22, 2026 - Booking Exception Workflows

### Changes
- Completed early-departure truncation and charge processing.
- Improved checkout-period validation and operational exception handling.

---

## May 21, 2026 - No-Show Accounting Hardening

### Changes
- Posted no-show room charges as `no_show_charge`.
- Kept no-show tax classified as `tax`.
- Made folio transaction category the accounting source of truth.
