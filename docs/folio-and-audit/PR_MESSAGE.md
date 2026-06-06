# PR: Folio & Audit — Booking Lifecycle, Financial Ledger, and Night Audit Foundation

## Background

WAStays is a multi-tenant hotel property management system (PMS) handling booking lifecycle, financial folios, payment processing, night audit, and reporting for hotel operators across Malaysia. The system has evolved through several maturation phases — from core booking engine and payment gateway integration through to enterprise-grade financial controls with immutable audit trails, general ledger mapping, and comprehensive reporting.

This PR captures the entirety of the Folio & Audit domain: the booking lifecycle state machine, the folio-based financial ledger, financial controls (posting guard, audit events, GL mapping), night audit orchestration, and the reporting suite.

## Proposal

Consolidate and document the existing Folio & Audit domain as a single coherent subsystem. The architecture follows three core principles:

- **Immutability** — Folio transactions are never edited or deleted; corrections use explicit reversals
- **State-Driven Controls** — `HotelBusinessDate` governs when financial activity is allowed
- **Atomic Auditing** — Every money-impacting action records an immutable `FinancialAuditEvent`

All revenue analytics reconcile to `FolioTransaction` (charges + adjustments) as the single source of truth, not the booking's `total_amount` field.

## Changes Made

### Created

- `docs/folio-and-audit/` — Complete operational documentation folder:
  - `completed-roadmaps/foundation.md` — Core foundation record
  - `completed-roadmaps/operational-maturation-phase-1.md` — Phase 1 maturation record
  - `current-progress-roadmaps/operational-maturation.md` — Remaining priorities
  - `knowledges/` — Feature-level knowledge records (booking lifecycle, folio, financial controls, night audit, reporting)
  - `planning/enterprise-features.md` — Forward-looking enterprise planning
  - `reference/night-audit-reference.md` — Target PMS operating model
- Folio models: `BookingFolio`, `FolioTransaction`, `Deposit`, `HotelGeneralLedgerMap`, `JournalBatch`, `JournalBatchEntry`
- Financial controls: `FinancialAuditEvent`, `HotelBusinessDate`, `PostingGuard`, `AuditEventRecorder`
- Night audit: `NightAudit`, `NightAuditLog`, `NightAuditFinancialSummary`, `RunNightAudit`, `EvaluateNightAudit`
- Report services: `DailyOccupancyReport`, `DailyRevenueReport`, `ManagersFlashReport`, `OutstandingBalanceReport`, `DepositLiabilityReport`, `ArrivalsDeparturesReport` + CSV/XLS/PDF export services
- Financial controls services: `PostingGuard`, `AuditEventRecorder`, `EvaluateAnomalies`
- Folio services: `InitializeForBooking`, `InsertTransaction`, `CloseForCheckout`, `PostNightlyCharges`, `ReverseTransaction`, `ProcessCatchUpCharges`, `RecordPaymentFromGateway`, `RecordRefund`, `PostStaffTransaction`, `PostCategoryCharge`, `ProcessCatchUpCharges`
- PDF services: `FolioInvoicePdfService`, `AuditPacketPdfExportService`

### Updated

- `Booking` model — Added `has_one :booking_folio`, `has_many :folio_transactions` (through folio), `has_one :pre_checkin`, `has_one :refund_request`, status lifecycle concern `Bookings::StatusLifecycle`
- `BookingRoom` model — Added `rate_plan` association, `room_number`
- `Hotel` model — Added `has_many :booking_folios`, `has_many :hotel_business_dates`, `has_many :journal_batches`, `has_many :night_audits`
- `User` model — Added granular folio permissions (`post_folio_charges`, `post_folio_payments`, `execute_folio_refunds`, `post_folio_adjustments`, `post_folio_corrections`, `post_folio_write_offs`, `override_financial_date_lock`)
- `HotelPortal::ReportsController` — Added actions for `daily_occupancy`, `daily_revenue`, `managers_flash`, `outstanding_balance`, `deposit_liability`, `arrivals_departures`, `folio_ledger`, `journal_batches`
- `HotelPortal::NightAuditsController` — Added `index`, `show`, `resolve`, `blockers`, `create`
- `Public::WebhooksController` — Generic payment webhook receiver

### Destroyed

- Legacy `post_folio_transactions` permission — Replaced by granular folio permissions
- Legacy `no_show_penalty` transaction category — Renamed to `no_show_charge` for GL/report consistency
- No-show accounting from metadata — Source of truth moved to `folio_transaction.category`
- Full-stay upfront charging model — Replaced by automated nightly charges via night audit

## Affected Files

### Models (17 files)

```
app/models/
├── booking.rb                           # has_one :booking_folio, status lifecycle
├── booking_room.rb                      # rate_plan association
├── booking_folio.rb                     # Financial ledger per booking
├── folio_transaction.rb                 # Immutable charge/payment/adjustment
├── deposit.rb                           # Security deposits
├── hotel_business_date.rb               # State machine: open/audit_running/closed
├── hotel_general_ledger_map.rb          # GL code mappings per hotel
├── journal_batch.rb                     # Night audit journal aggregation
├── journal_batch_entry.rb               # Individual journal debit/credit lines
├── financial_audit_event.rb             # Immutable audit trail
├── night_audit.rb                       # Night audit trigger configuration
├── night_audit_log.rb                   # Night audit execution log
├── night_audit_financial_summary.rb     # Persisted daily financial totals
├── payment_transaction.rb               # Gateway transaction records
├── refund_request.rb                    # Guest-initiated refund workflow
├── payout_batch.rb                      # Weekly payout grouping
└── concerns/bookings/status_lifecycle.rb # Booking state machine
```

### Services (60+ files)

```
app/services/bookings/
├── create_manual_booking.rb
├── transition_status.rb
├── process_no_shows.rb
├── process_early_departure.rb
├── reinstate_reservation.rb
├── build_financial_snapshot.rb
├── assign_room.rb
├── inventory_manager.rb
├── record_audit_log.rb
└── webhook_trigger_service.rb

app/services/folios/
├── initialize_for_booking.rb           # Folio creation at check-in/no-show
├── insert_transaction.rb                # Core transaction gateway
├── close_for_checkout.rb                # Folio closure at departure
├── post_nightly_charges.rb              # Automated daily charges
├── post_category_charge.rb              # Late checkout / early departure charges
├── post_early_checkout_charges.rb       # Final charges before truncation
├── post_staff_transaction.rb            # Staff-initiated manual postings
├── reverse_transaction.rb               # Immutable reversal via offset
├── record_payment_from_gateway.rb       # Sync gateway payment to folio
├── record_refund.rb                     # Sync refund completion to folio
├── process_catch_up_charges.rb          # Retroactive charge posting
├── sync_existing_payments.rb            # Payment sync on folio init
└── nightly_charge_calculation.rb        # Per-night rate snapshot concern

app/services/financial_controls/
├── posting_guard.rb                     # Business date enforcement
├── audit_event_recorder.rb              # Immutable audit event recording
└── evaluate_anomalies.rb               # Background anomaly detection

app/services/financials/
├── create_journal_batch.rb              # GL journal aggregation
└── ensure_default_gl_maps.rb            # Default GL code seeding

app/services/payments/
├── base_adapter.rb                      # Gateway adapter interface
├── gateway_registry.rb                  # Factory: razorpay / curlec
├── initialize_checkout.rb               # Checkout session creation
├── process_verification.rb              # Client callback verification
├── transaction_recorder.rb              # PaymentTransaction recording
└── gateway_adapters/
    ├── razorpay.rb
    └── curlec.rb

app/services/hotel_ops/
├── run_night_audit.rb                   # Night audit orchestrator
├── evaluate_night_audit.rb              # Blocker detection engine
├── calculate_business_day_financials.rb # Daily financial calculation
├── recalculate_night_audit_summary.rb   # Summary recalculation
└── audit_packet_pdf_export_service.rb   # Full audit packet PDF

app/services/hotel_portal/reports/
├── daily_occupancy_report.rb
├── daily_revenue_report.rb
├── managers_flash_report.rb
├── outstanding_balance_report.rb
├── deposit_liability_report.rb
├── arrivals_departures_report.rb
├── financial_performance_export_service.rb
├── financial_breakdown_export_service.rb
├── payouts_export_service.rb
├── journal_batch_csv_export_service.rb
├── daily_occupancy_{csv,excel,pdf}_export_service.rb
├── daily_revenue_{csv,excel,pdf}_export_service.rb
├── managers_flash_{csv,excel,pdf}_export_service.rb
├── outstanding_balance_{csv,excel,pdf}_export_service.rb
├── deposit_liability_{csv,excel,pdf}_export_service.rb
└── arrivals_departures_{csv,excel,pdf}_export_service.rb

app/services/
├── folio_invoice_pdf_service.rb
├── invoice_pdf_service.rb
├── receipt_pdf_service.rb
├── folio_ledger_export_service.rb
├── payout_export_service.rb
└── booking_export_service.rb

app/services/deposits/
└── record_security_deposit.rb

app/services/refunds/
└── submit_request.rb

app/services/payout_engine/
└── generate_weekly_batches.rb
```

### Controllers (16 files)

```
app/controllers/
├── hotel_portal/
│   ├── bookings_controller.rb
│   ├── folio_transactions_controller.rb
│   ├── general_ledger_maps_controller.rb
│   ├── night_audits_controller.rb
│   ├── reports_controller.rb
│   ├── checkout_requests_controller.rb
│   └── reservation_board/board_bookings_controller.rb
├── public/
│   ├── payments_controller.rb
│   ├── webhooks_controller.rb
│   ├── channel_manager_webhooks_controller.rb
│   ├── concierge/check_ins_controller.rb
│   └── concierge/check_outs_controller.rb
├── guest/
│   ├── bookings_controller.rb
│   └── refund_requests_controller.rb
├── admin/
│   ├── bookings_controller.rb
│   ├── refund_requests_controller.rb
│   ├── payout_batches_controller.rb
│   ├── payouts_controller.rb
│   └── reconciliations_controller.rb
└── concerns/
    └── financial_filtering.rb
```

### Jobs (6 files)

```
app/jobs/
├── run_scheduled_night_audits_job.rb
├── financial_observability_job.rb
├── hotel_ops/run_night_audit_job.rb
├── send_receipt_email_job.rb
├── send_invoice_email_job.rb
├── send_whatsapp_receipt_job.rb
└── send_whatsapp_invoice_job.rb
```

### Mailers (4 files)

```
app/mailers/
├── booking_mailer.rb
├── refund_mailer.rb
├── finance_alert_mailer.rb
└── guest_mailer.rb
```

### Migrations (40+ migrations)

```
db/migrate/
├── 20260514082024_create_booking_folios.rb
├── 20260515000107_create_folio_transactions.rb
├── 20260515002929_create_night_audit_logs.rb
├── 20260518052729_create_night_audit_financial_summaries.rb
├── 20260519232734_add_invoice_number_to_booking_folios.rb
├── 20260520000000_create_hotel_business_dates.rb
├── 20260520001000_add_override_financial_date_lock_permission.rb
├── 20260520002000_create_financial_audit_events.rb
├── 20260520064533_add_gl_code_to_folio_transactions_and_create_hotel_general_ledger_maps.rb
├── 20260520064754_create_journal_batches.rb
├── 20260520070000_add_granular_folio_permissions.rb
├── 20260521000100_create_deposits.rb
├── 20260521000200_rename_advance_deposits_to_booking_payments.rb
├── 20260521135928_add_adjustments_total_to_night_audit_financial_summaries.rb
├── 20260522140000_rename_penalty_categories_to_charges.rb
├── 20260522140001_rename_gl_map_penalty_transaction_categories.rb
├── 20260522140002_rename_no_show_penalties_to_no_show_charges.rb
└── 20260522140003_harden_booking_financial_precision.rb
```

### Documentation (10+ files)

```
docs/folio-and-audit/
├── README.md
├── completed-roadmaps/
│   ├── foundation.md
│   └── operational-maturation-phase-1.md
├── current-progress-roadmaps/
│   └── operational-maturation.md
├── knowledges/
│   ├── booking-lifecycle/
│   │   ├── 1-status-lifecycle.md
│   │   ├── 2-check-in-check-out.md
│   │   └── 3-no-show-processing.md
│   ├── folio/
│   │   ├── 1-folio-initialization.md
│   │   ├── 2-folio-transactions.md
│   │   ├── 3-nightly-charges.md
│   │   ├── 4-payments-refunds-reversals.md
│   │   └── 5-checkout-settlement.md
│   ├── financial-contracts/
│   │   ├── 1-posting-guard.md
│   │   ├── 2-financial-audit-events.md
│   │   ├── 3-general-ledger-mapping.md
│   │   ├── 4-immutability-and-reversals.md
│   │   └── 5-financial-observability.md
│   ├── night-audit/
│   │   ├── 1-business-date-governance.md
│   │   ├── 2-audit-evaluation-blockers.md
│   │   ├── 3-run-night-audit.md
│   │   └── 4-journal-batch-and-reports.md
│   └── reporting/
│       └── 1-managers-flash-report.md
├── planning/
│   └── enterprise-features.md
└── reference/
    └── night-audit-reference.md
```

## File Structure (Domain Tree)

```
app/
├── models/                             17 domain models
├── services/                           60+ domain services
│   ├── bookings/                       11
│   ├── folios/                         13
│   ├── financial_controls/              3
│   ├── financials/                      2
│   ├── payments/                        6 (incl. 2 adapters)
│   ├── hotel_ops/                       5
│   ├── hotel_portal/reports/           28
│   └── deposits/ refunds/ payout_engine/
├── controllers/                        16 domain controllers
├── jobs/                                7 domain jobs
├── mailers/                             4 domain mailers
└── views/                              N/A (REST + Hotwire)

db/
└── schema.rb                           77 tables

docs/
└── folio-and-audit/                    17 documentation files
```

## Key Architectural Decisions

| Decision | Rationale |
|----------|-----------|
| FolioTransaction immutability | Corrections via explicit reversal prevents data loss and provides full audit trail |
| FolioTransaction as SSOT for revenue | Avoids drift between booking amounts and actual posted charges |
| HotelBusinessDate state machine | Prevents financial postings into closed/in-flight periods |
| Granular folio permissions | Replaces broad `post_folio_transactions` with charge/payment/adjustment/correction/reversal-specific permissions |
| Per-night charge posting | Replaces full-stay upfront charging for accurate per-date revenue recognition |
| Automated journal batching | Groups folio transactions by GL code for direct accounting export |
| Force Roll capability | Prevents operational standstill when night audit is blocked; recorded as `force_closed` audit event |
