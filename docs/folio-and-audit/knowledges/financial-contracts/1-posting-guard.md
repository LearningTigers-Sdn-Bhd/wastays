# Financial Contracts: Posting Guard

## Status

Completed foundation.

## Purpose

Centralizes whether a transaction can post to a business date based on date state, source, actor, and override permission.

## Key Files

- `app/services/financial_controls/posting_guard.rb`
- `app/services/folios/insert_transaction.rb`
- `app/services/folios/post_staff_transaction.rb`
- `spec/services/financial_controls/posting_guard_spec.rb`

## Rules Made So Far

- Normal postings are blocked for closed or protected business dates.
- Authorized closed-date overrides require explicit permission and audit reason.
- Folio insertion paths use the guard before committing financial activity.

## Known Follow-Ups

- Split broad financial powers into granular permissions such as refund execution, write-off posting, correction posting, and date override.
- Add monitoring for excessive closed-date override use.
