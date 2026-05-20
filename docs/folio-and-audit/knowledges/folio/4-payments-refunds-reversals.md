# Folio: Payments, Refunds, And Reversals

## Status

Mostly completed foundation; refund approval workflow remains current-progress work.

## Purpose

Keeps money movement auditable by recording gateway payments, manual payments, refunds, and corrections as explicit ledger entries.

## Key Files

- `app/services/folios/record_payment_from_gateway.rb`
- `app/services/folios/record_refund.rb`
- `app/services/folios/reverse_transaction.rb`
- `app/services/folios/post_staff_transaction.rb`
- `spec/services/folios/reverse_transaction_spec.rb`

## Rules Made So Far

- Captured payments can be reflected on guest folios.
- Refunds are recorded as folio transactions instead of mutating original payment entries.
- Reversals create explicit reversing transactions and preserve the original transaction.
- Reversal and refund actions flow through audit controls.
- Manual refunds require `execute_folio_refunds`.
- Reversals require `post_folio_corrections`.

## Known Follow-Ups

- Add multi-stage approval for high-value refunds.
- Link refund ledger entries to original payment gateway identifiers in staff-facing reconciliation views.
