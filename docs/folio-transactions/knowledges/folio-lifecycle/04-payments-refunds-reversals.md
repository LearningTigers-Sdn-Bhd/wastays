# Folio: Payments, Refunds, And Reversals

## Status

Basic payments, refunds, and reversals are implemented. Enterprise multi-stage refund approval is deferred to a future phase.

## Purpose

Keeps money movement auditable by recording gateway payments, manual payments, refunds, and corrections as explicit ledger entries.

## Key Files

- `app/services/folios/record_payment_from_gateway.rb`
- `app/services/folios/record_refund.rb`
- `app/services/folios/reverse_transaction.rb`
- `app/services/folios/post_staff_transaction.rb`
- `app/models/refund_request.rb`
- `app/controllers/admin/refund_requests_controller.rb`
- `docs/folio-transactions/knowledges/folio-lifecycle/06-refund-lifecycle.md`
- `spec/services/folios/reverse_transaction_spec.rb`

## Rules Made So Far

- Captured payments can be reflected on guest folios.
- Refunds are recorded as folio transactions instead of mutating original payment entries.
- Completed refund requests are recorded through `Folios::RecordRefund` as negative `payment/refund` folio transactions.
- Refund folio postings include `metadata["refund_request_id"]` for traceability and idempotency.
- Reversals create explicit reversing transactions and preserve the original transaction.
- Reversing an actualized nightly charge supersedes the linked forecast and runs `Folios::SyncForecastedCharges`, allowing checkout validation to detect the night as missing again when the booking still requires a posted charge.
- Reversal and refund actions flow through audit controls.
- Manual refunds require `execute_folio_refunds`.
- Reversals require `post_folio_corrections`.
- Night audit detects completed refund requests that have not been synced to the folio as `refund_not_synced` blockers.

## Known Follow-Ups (Deferred / Unplanned)

- Add multi-stage approval for high-value refunds.
- Link refund ledger entries to original payment gateway identifiers in staff-facing reconciliation views.
- Decide whether admin refund completion should trigger automated gateway refund execution or remain a manual settlement confirmation.
