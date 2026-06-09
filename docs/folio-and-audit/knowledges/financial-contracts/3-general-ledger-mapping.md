# Financial Contracts: General Ledger Mapping

## Status

Completed foundation with remaining export alignment work.

## Purpose

Maps folio transaction categories to accounting General Ledger Codes (GL Codes) and supports hotel-specific configuration for journal exports.

## Key Files

- `app/models/hotel_general_ledger_map.rb`
- `app/services/financials/ensure_default_gl_maps.rb`
- `app/services/financials/create_journal_batch.rb`
- `app/controllers/hotel_portal/general_ledger_maps_controller.rb`
- `app/services/hotel_portal/reports/journal_batch_csv_export_service.rb`
- `app/services/folio_ledger_export_service.rb`
- `spec/services/financials/create_journal_batch_spec.rb`
- `spec/services/folio_ledger_export_service_spec.rb`

## Rules Made So Far

- Hotels can manage General Ledger (GL) mappings for supported financial categories.
- Default General Ledger (GL) mappings exist for every valid folio transaction category.
- Journal batches can be created from business-day financial activity.
- Journal batch creation fails fast if any business-day folio transaction is missing a General Ledger Code (GL Code).
- Journal batch CSV export supports accounting reconciliation.
- `no_show_charge` maps separately from accommodation revenue for deterministic no-show accounting.

## Known Follow-Ups

- Align folio ledger export fallback behavior with hotel-specific General Ledger (GL) mappings so export issues fail visibly instead of using generic fallback codes.

## Default General Ledger Mappings

| Transaction Category | General Ledger Code (GL Code) | System Description | Detailed Explanation |
| :--- | :--- | :--- | :--- |
| `accommodation` | `4010` | Room Revenue | Nightly room rates, room upgrades, and standard stay charges applied to guest folios. |
| `tax` | `2010` | Tax Liabilities | State, local, and occupancy taxes collected from guests that the hotel owes to the government. |
| `fb` | `4020` | Food & Beverage Revenue | Charges from hotel restaurants, bars, room service, or minibar consumption. |
| `no_show_charge` | `4030` | No-Show Charge Revenue | Fees captured when a guest fails to arrive for a guaranteed reservation. Kept separate from `accommodation` to avoid skewing Average Daily Rate (ADR) and occupancy metrics. |
| `other` | `4090` | Other Revenue | Miscellaneous ancillary services like parking, spa, laundry, or pet fees. |
| `gateway_payment` | `1010` | Bank - Gateway | Electronic payments (credit/debit cards) processed automatically through external payment gateways like Stripe. |
| `cash` | `1020` | Bank - Cash | Physical currency (bills and coins) collected in person at the front desk. |
| `refund` | `1030` | Bank - Refunds | Outbound money returned to the guest, typically reversing a previous `gateway_payment` or `cash` transaction. |
| `booking_payment` | `2020` | Booking Payment Liability | Pre-payments collected for the booking before stay revenue is earned. |
| `security_deposits` | `2030` | Security Deposit Liability | Actual check-in security deposits held separately from the guest folio until released or applied. |
| `adjustment` | `5010` | Adjustments | Post-audit reductions to revenue, often due to guest complaints or service recovery efforts (e.g., reducing the room rate because the AC was broken). |
| `correction` | `5020` | Corrections | Same-day fixes for human errors made before the night audit closes (e.g., voiding a charge accidentally posted to the wrong room). |
| `discount` | `5030` | Discounts | Upfront percentage or fixed-amount price reductions applied proactively to standard rates. |
| `write_off` | `5040` | Write-Offs | Unpaid guest folio balances that the hotel has deemed uncollectible (bad debt) and absorbs as a loss. |
