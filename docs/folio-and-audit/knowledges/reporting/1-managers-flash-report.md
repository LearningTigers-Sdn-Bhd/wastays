# Reporting: Manager's Flash Report

## Status

Completed May 22, 2026.

## Purpose

Provides a unified daily management view of the property's performance, combining occupancy metrics with actual posted revenue.

## Key Files

- `app/services/hotel_portal/reports/managers_flash_report.rb`
- `app/services/hotel_portal/reports/managers_flash_pdf_export_service.rb`
- `app/services/hotel_portal/reports/managers_flash_csv_export_service.rb`
- `app/services/hotel_portal/reports/managers_flash_excel_export_service.rb`
- `app/controllers/hotel_portal/reports_controller.rb`
- `app/views/hotel_portal/reports/managers_flash.html.erb`
- `spec/services/hotel_portal/reports/managers_flash_report_spec.rb`

## Rules Made So Far

- **Optimized Data Aggregation:** Uses custom SQL queries to efficiently calculate Occupancy %, ADR, RevPAR, and Daily Revenue in a single pass.
- **Prorated Booking Revenue:** Calculates ADR and RevPAR based on prorated booking subtotals to align with industry standards and the `DailyOccupancyReport`.
- **Actual Posted Revenue:** Displays actual room revenue and tax posted to guest folios, aligning with the `DailyRevenueReport`.
- **Multi-Format Exports:** Supports professional PDF (landscape), Excel (multi-sheet), and CSV exports.
- **Access Control:** Protected by the `view_reports` permission.
- **Ledger Grid UI:** Features a high-contrast, unified ledger grid that ensures perfectly equal card heights and pins key values to the bottom for superior readability.

## Metric Definitions

The Manager Flash Report combines two distinct views of property performance: **Operational Efficiency** (based on bookings) and **Financial Actuals** (based on the ledger).

### 1. Operational Efficiency (Performance KPIs)
These metrics use **prorated booking subtotals** to evaluate how effectively the hotel is selling its inventory. They provide an "earned" view of revenue regardless of when the charges were actually posted.

| Metric | Definition | Calculation |
| :--- | :--- | :--- |
| **Occupancy %** | The percentage of available rooms that were sold for the night. | `Rooms Sold / Rooms Available` |
| **ADR** | Average Daily Rate. The average price paid for each sold room. | `Total Prorated Booking Revenue / Rooms Sold` |
| **RevPAR** | Revenue Per Available Room. Measures total revenue generation against total capacity. | `Total Prorated Booking Revenue / Total Rooms Available` |

### 2. Financial Actuals (Ledger Totals)
These metrics represent the **actual money posted to folios** on that specific business date. They are the "source of truth" for accounting and reconciliation.

| Metric | Definition | Calculation |
| :--- | :--- | :--- |
| **Room Revenue** | The total amount of `accommodation` charges (and related adjustments) posted to folios. | `SUM(Folio Transactions where category = 'accommodation')` |
| **Tax** | Total taxes (VAT, City Tax, etc.) collected on the business date. | `SUM(Folio Transactions where category = 'tax')` |
| **Other Revenue** | All ancillary charges (F&B, No-Show, Late Checkout, etc.) posted to folios. | `SUM(Folio Transactions where category NOT IN ('accommodation', 'tax'))` |
| **Total Revenue** | The sum of all room, tax, and other revenue posted to the property's ledger. | `Room Revenue + Tax + Other Revenue` |

## Known Follow-Ups

- Align folio ledger export fallback behavior with hotel-specific GL mappings.
- Implement the "Blocker Dashboard" UX for interactive exception resolution.
