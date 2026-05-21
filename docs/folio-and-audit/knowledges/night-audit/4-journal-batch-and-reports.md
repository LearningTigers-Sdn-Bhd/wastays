# Night Audit: Journal Batch And Reports

## Status

Partially completed.

## Purpose

Turns closed business-day activity into financial summaries, journal batches, and operational reports.

## Key Files

- `app/services/financials/create_journal_batch.rb`
- `app/models/journal_batch.rb`
- `app/models/journal_batch_entry.rb`
- `app/controllers/hotel_portal/reports_controller.rb`
- `app/services/hotel_portal/reports/daily_revenue_report.rb`
- `app/services/hotel_portal/reports/daily_occupancy_report.rb`
- `app/services/hotel_portal/reports/outstanding_balance_report.rb`
- `app/services/hotel_portal/reports/deposit_liability_report.rb`
- `app/services/hotel_portal/reports/arrivals_departures_report.rb`
- `app/services/hotel_portal/reports/journal_batch_csv_export_service.rb`
- `spec/services/financials/create_journal_batch_spec.rb`
- `spec/services/hotel_portal/reports/deposit_liability_report_spec.rb`
- `spec/requests/hotel_portal/reports_spec.rb`

## Rules Made So Far

- Successful night audit can create journal batches for accounting reconciliation.
- Daily revenue, occupancy, outstanding balance, deposit liability, arrivals/departures, folio ledger, and journal batch exports exist.
- Manager Flash Report (Occupancy, ADR, RevPAR, and Daily Revenue) implemented with optimized custom SQL queries and multi-format exports.
- `daily_revenue` and `managers_flash` are protected by `view_reports` authorization.
- Journal batch creation fails fast when any included transaction is missing a GL code.
- Journal batch CSV export supports external accounting workflows.
- Deposit Liability Report tracks unearned advance-deposit balances.

## Known Follow-Ups

- Generate a complete audit packet after close.
- Align folio ledger export with hotel-specific GL mappings.
