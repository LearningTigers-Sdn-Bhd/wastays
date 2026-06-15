# Folio: Checkout Settlement

## Status

Completed foundation. Double-counting fix applied June 10, 2026.

## Purpose

Prevents guest departure from closing financially until all earned charges are posted and the folio is settled.

## Key Files

- `app/services/folios/close_for_checkout.rb`
- `app/services/folios/sync_forecasted_charges.rb`
- `app/services/folios/post_early_checkout_charges.rb` — `projected_checkout_balance` class method
- `app/services/bookings/transition_status.rb`
- `app/services/bookings/process_early_departure.rb`
- `app/services/folio_invoice_pdf_service.rb`
- `app/models/booking_folio.rb` — `unsettled_forecasts`, `projected_forecasts`, `all_charges_posted?` helpers
- `app/controllers/hotel_portal/bookings/checkouts_controller.rb`
- `app/views/hotel_portal/bookings/_checkout_sheet.html.erb` — checkout offcanvas with Resolve Balance card
- `app/views/hotel_portal/bookings/show/modals/_checkout_modal.html.erb` — quick checkout dialog

## Rules Made So Far

- Checkout closure is blocked for positive balances.
- Credit balances must be resolved before closure.
- Checkout runs `SyncForecastedCharges` before missing-charge validation so existing open folios without forecast rows cannot bypass validation.
- Missing nightly charges block checkout (detected via unsettled forecast records for stay dates before the current checkout date).
- Closed folios can produce itemized invoice or receipt output.
- The checkout sheet's "Resolve Balance" card uses `projected_checkout_balance` to determine what state to show: payment required (positive), refund needed (negative), or ready to close (zero).
- For early departures, `projected_checkout_balance` must avoid double-counting: regular forecasted charges for unused nights are included in `projected_outstanding_balance`, and early departure charges are added on top. The `PostEarlyCheckoutCharges.projected_checkout_balance` method resolves this by computing `outstanding_balance + pending_early_departure_charges`, skipping the overlapping forecasts entirely.

## Checkout UI Flow

The checkout flow has two entry points from the show booking page:

1. **Quick checkout dialog** (`_checkout_modal.html.erb`) — a simple `<dialog>` showing folio number, projected balance, and a datetime picker. Used for quick confirmations.

2. **Full checkout sheet** (`_checkout_sheet.html.erb`) — a fullscreen-bottom offcanvas drawer opened via Turbo Frame. Contains:
   - Folio balance summary (projected charges, payments, outstanding balance)
   - Checkout time picker
   - Early departure review (with optional charge, shown when departing before scheduled check-out)
   - Security deposit status
   - **Resolve Balance card** — shows one of five states:
     - Folio required (folio is nil)
     - Payment required (`projected_checkout_balance > 0`)
     - Credit balance detected (`projected_checkout_balance < 0`)
     - Folio already closed
     - Ready to close folio (balance is zero)
   - Transaction ledger table

## Double-Counting Fix

### Problem

During early departure, the checkout sheet's `projected_checkout_balance` included both regular forecasted charges for unused nights (via `projected_outstanding_balance`) and early departure charges for those same nights (via `early_checkout_total`), inflating the balance shown in the Resolve Balance card.

```ruby
# Before (double-counted):
projected_checkout_balance = balance + early_checkout_total
# where balance = outstanding_balance + projected_forecasts.sum
```

### Example

4-night stay at $250/night, fully prepaid via `booking_payment` of $1,000. Guest checks out early after 2 nights:

| Component | Value |
|---|---|
| Actual posted charges (2 nights) | $500 |
| Booking payment | $1,000 |
| `outstanding_balance` | -$500 |
| Regular forecasts (nights 3-4) | +$500 |
| `projected_outstanding_balance` | $0 |
| Early departure charges (nights 3-4) | +$500 |
| **Old `projected_checkout_balance`** | **$500** → showed "Payment required" incorrectly |

After processing, the actual balance would be $0 (early departure charges posted, regular forecasts superseded).

### Fix

`Folios::PostEarlyCheckoutCharges.projected_checkout_balance` computes `outstanding_balance + pending_early_departure_charges` — using the actual posted balance (no forecasts) as the baseline, then adding only the early departure charges that will replace the superseded forecasts.

```ruby
# After (correct):
projected_checkout_balance = folio.outstanding_balance + pending_early_charges
```

For the example: `-$500 + $500 = $0` → shows "Ready to close folio" correctly.

### Implementation

- Service method: `Folios::PostEarlyCheckoutCharges.projected_checkout_balance(folio:, departure_date:, original_check_out:)`
- View: `_checkout_sheet.html.erb:9` — uses the new method for early departure, falls back to `balance` otherwise

## Known Follow-Ups

- Improve user guidance around why checkout is blocked and what action resolves it.
- Include audit-packet links once current-progress reporting is complete.
