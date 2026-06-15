# PR: Night Audits and Financial Reconciliation Foundation

## Background

WAStays requires a controlled daily close that turns operational activity into an auditable business-day record without duplicate posting or unsafe date advancement.

## Solution

- Added hotel business dates, blocker evaluation, scheduled and manual night-audit execution, and atomic day roll.
- Added immutable financial audit events, General Ledger mappings, journal batches, daily summaries, and operational reports.
- Added blocker review, Audit Packet generation, anomaly monitoring, and authorized force roll.

## Domain Boundaries

- Night audits owns business-date governance, reconciliation, audit evidence, and closing reports.
- Folio transactions owns the immutable entries consumed by audit and accounting.
- Hotel bookings owns reservation and stay-state transitions consumed by audit.

## Verification

Use service, request, system, report-export, and concurrency specs covering `HotelOps`, financial controls, journal batching, and reporting.
