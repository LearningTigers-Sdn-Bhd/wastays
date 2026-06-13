# Folio: Nightly Charges

## Status

Completed foundation.

## Purpose

Posts room revenue and tax by business date during night audit instead of charging the full stay upfront.

## Key Files

- `app/services/folios/post_nightly_charges.rb`
- `app/services/folios/nightly_charge_calculation.rb`
- `app/services/folios/generate_forecasted_charges.rb`
- `app/services/folios/sync_forecasted_charges.rb`
- `app/models/folio_forecasted_charge.rb`
- `app/services/hotel_ops/run_night_audit.rb`
- `app/models/hotel_tax.rb`
- `spec/services/folios/post_nightly_charges_spec.rb`
- `spec/services/folios/nightly_charge_calculation_spec.rb`
- `spec/services/folios/generate_forecasted_charges_spec.rb`

## Rules Made So Far

- Nightly charges are posted for occupied nights, not checkout day.
- Accommodation and tax are posted as separate folio lines.
- Duplicate nightly postings for the same booking and business date are prevented.
- Nightly postings are run as part of the night audit close flow.
- Successfully posted nightly charges actualize matching forecast records, linking the real `FolioTransaction` via `actualizing_transaction_id` and marking the forecast as `actualized`.
- If a night audit retry finds that the nightly charge already exists, it still actualizes the matching forecast so partial crash/retry paths do not leave stale pending rows.

## Known Follow-Ups

- Extend package posting if rate plans include bundled items such as breakfast or parking.
- Confirm tax component granularity is sufficient for each supported jurisdiction.
