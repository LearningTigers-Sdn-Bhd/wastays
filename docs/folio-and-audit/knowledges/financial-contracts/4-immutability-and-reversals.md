# Financial Contracts: Immutability And Reversals

## Status

Completed foundation.

## Purpose

Protects the financial ledger by making posted transactions append-only and requiring corrections through explicit reversal or adjustment entries.

## Key Files

- `app/models/folio_transaction.rb`
- `app/services/folios/reverse_transaction.rb`
- `app/services/folios/insert_transaction.rb`
- `spec/models/folio_transaction_spec.rb`
- `spec/services/folios/reverse_transaction_spec.rb`

## Rules Made So Far

- Posted transactions are not edited or deleted for business corrections.
- Reversals create new transactions linked to the original transaction.
- Corrections preserve ledger history and audit evidence.

## Known Follow-Ups

- Keep all new financial workflows append-only by default.
- Ensure reporting distinguishes original postings, reversals, write-offs, discounts, and corrections clearly.
