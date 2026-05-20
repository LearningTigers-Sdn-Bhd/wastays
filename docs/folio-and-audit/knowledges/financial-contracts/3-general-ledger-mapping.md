# Financial Contracts: General Ledger Mapping

## Status

Partially completed.

## Purpose

Maps folio transaction categories to accounting GL codes and supports hotel-specific configuration for journal exports.

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

- Hotels can manage GL mappings for supported financial categories.
- Journal batches can be created from business-day financial activity.
- Journal batch creation fails fast if any business-day folio transaction is missing a GL code.
- Journal batch CSV export supports accounting reconciliation.

## Known Follow-Ups

- Seed default mappings for every valid folio transaction category.
- Add tests that fail when a valid category lacks a default GL mapping.
