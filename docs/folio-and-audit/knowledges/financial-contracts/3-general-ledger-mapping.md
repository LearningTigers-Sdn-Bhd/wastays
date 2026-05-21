# Financial Contracts: General Ledger Mapping

## Status

Completed foundation with remaining export alignment work.

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
- Default GL mappings exist for every valid folio transaction category.
- Journal batches can be created from business-day financial activity.
- Journal batch creation fails fast if any business-day folio transaction is missing a GL code.
- Journal batch CSV export supports accounting reconciliation.
- `no_show_penalty` maps separately from accommodation revenue for deterministic no-show accounting.

## Known Follow-Ups

- Align folio ledger export fallback behavior with hotel-specific GL mappings so export issues fail visibly instead of using generic fallback codes.
