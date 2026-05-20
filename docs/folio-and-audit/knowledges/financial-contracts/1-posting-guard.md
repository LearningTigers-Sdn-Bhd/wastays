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
- Staff folio postings are authorized with granular permissions before reaching the posting guard.
- Closed business-date override remains separately controlled by `override_financial_date_lock`.

## Known Follow-Ups

- Add monitoring for excessive closed-date override use.
