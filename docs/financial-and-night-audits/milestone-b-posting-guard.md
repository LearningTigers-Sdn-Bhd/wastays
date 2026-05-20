# Milestone B: Posting Guard

## Goal

Enforce `HotelBusinessDate` states at financial posting boundaries so folio transactions and checkout actions cannot accidentally post into restricted business dates.

Milestone B builds on Milestone A by turning business-date state into an operational control.

## Implemented Scope

Milestone B delivered:

1. `FinancialControls::PostingGuard`.
2. `override_financial_date_lock` permission.
3. Guard enforcement in `Folios::InsertTransaction`.
4. Guard enforcement in `Folios::CloseForCheckout`.
5. Audit-owned posting support for nightly charges and no-show charges.
6. Blocker-resolution posting support for `audit_blocked` dates.
7. Closed/reopened date override support with permission and reason.
8. Closed-date gateway payment sync now blocks by default instead of silently overriding.
9. Specs for guard behavior and key integration paths.

## Business-Date Posting Rules

| Business-Date State | Normal Posting | Night Audit Posting | Blocker-Resolution Posting | Override Posting |
|---|---:|---:|---:|---:|
| `open` | Allowed | Allowed | Allowed | Not needed |
| `audit_running` | Blocked | Allowed | Blocked | Not allowed |
| `audit_blocked` | Blocked | Blocked | Allowed with context | No general override |
| `closed` | Blocked | Blocked | Blocked | Allowed with permission and reason |
| `reopened` | Blocked by default | Blocked | Blocked | Allowed with permission and reason |
| `force_closed` | Blocked | Blocked | Blocked | Not allowed in Milestone B |

## Posting Sources

The guard recognizes these source categories:

```text
staff
checkout
adjustment
reversal
night_audit
no_show
audit_blocker_resolution
closed_date_override
```

The implementation currently treats these as audit-owned sources during `audit_running`:

```text
night_audit
no_show
```

`audit_blocker_resolution` is allowed only during `audit_blocked` when required blocker context and reason are present.

## Guard API

`FinancialControls::PostingGuard` is called with:

```ruby
FinancialControls::PostingGuard.call!(
  hotel:,
  business_date:,
  actor:,
  posting_source:,
  override: false,
  override_reason: nil,
  permission_context: nil,
  blocker_resolution: nil
)
```

The guard raises a domain error when posting is blocked.

Main errors:

```ruby
FinancialControls::PostingGuard::PostingBlocked
FinancialControls::PostingGuard::OverrideReasonRequired
FinancialControls::PostingGuard::PermissionRequired
```

## Permission

Milestone B added:

```text
override_financial_date_lock
```

The migration assigns it to:

```text
hotel_owner
```

Superadmins are also allowed by existing permission behavior.

This permission is required for posting into `closed` and `reopened` business dates with override.

## Integration Points

### `Folios::InsertTransaction`

This is the primary enforcement point.

Before a `FolioTransaction` is created, it calls `FinancialControls::PostingGuard` using:

1. Folio hotel.
2. Transaction `posting_date`.
3. Posting actor.
4. Posting source from options or metadata.
5. Override flag and correction reason.
6. Optional blocker-resolution context.

This protects most charge, payment, adjustment, refund, reversal, catch-up, and system sync paths that create folio transactions.

### `Folios::CloseForCheckout`

Checkout now checks the hotel's business date for the checkout timestamp before closing the folio.

This blocks checkout completion while the relevant business date is `audit_running`, `audit_blocked`, `closed`, or `force_closed` unless a later milestone introduces an explicit permitted workflow.

### `Folios::PostNightlyCharges`

Nightly room and tax charges pass:

```ruby
posting_source: "night_audit"
```

This allows normal night-audit postings during `audit_running`.

### `Bookings::ProcessNoShows`

No-show penalties keep persisted metadata:

```ruby
posting_source: "no_show"
```

`no_show` is treated as an audit-owned source by the guard, allowing these postings during `audit_running` while preserving accurate transaction metadata.

### Gateway Payment And Refund Sync

Gateway payment and refund services pass explicit posting sources:

```text
gateway_payment
```

Gateway payments into closed business dates now block by default. They no longer silently create closed-date override postings without an authorized actor.

### Reversals

Reversal postings now use:

```text
reversal
```

This means reversals are subject to the same business-date controls as other financial postings.

### Existing Payment Sync

Existing captured payment sync now passes:

```text
gateway_payment
```

If it needs to post into a closed date, it must have an authorized override context.

## Audit-Blocked Resolution Rules

During `audit_blocked`, the guard allows only:

```text
audit_blocker_resolution
```

Required context:

```ruby
{
  night_audit_id:,
  blocker_type:
}
```

A non-blank reason is also required.

Recommended blocker types:

```text
missing_folio
missing_nightly_charges
outstanding_folio_balance
captured_payment_not_synced
refund_not_synced
```

General staff charges, refunds, payments, adjustments, checkout, and reversals remain blocked while the date is `audit_blocked` unless they are explicitly routed through blocker-resolution context.

## Missing Business-Date Rows

The guard handles missing `HotelBusinessDate` rows conservatively:

1. If a running night audit exists, treat the date as `audit_running`.
2. If a blocked night audit exists, treat the date as `audit_blocked`.
3. If a completed night audit exists, treat the date as `closed`.
4. If the date is current or future relative to the hotel's business date, treat it as `open`.
5. Otherwise, treat it as `closed`.

This avoids creating open historical rows during posting checks.

## Verification

Milestone B was verified with:

```sh
bin/rails db:migrate
bundle exec rspec
bundle exec rubocop app/services/financial_controls/posting_guard.rb app/services/folios/insert_transaction.rb app/services/folios/close_for_checkout.rb app/services/folios/post_nightly_charges.rb app/services/bookings/process_no_shows.rb app/services/folios/reverse_transaction.rb app/services/folios/record_payment_from_gateway.rb app/services/folios/record_refund.rb app/services/folios/sync_existing_payments.rb db/migrate/20260520001000_add_override_financial_date_lock_permission.rb spec/services/financial_controls/posting_guard_spec.rb spec/services/folios/insert_transaction_spec.rb spec/services/folios/process_catch_up_charges_spec.rb spec/services/folios/close_for_checkout_spec.rb spec/services/folios/record_payment_from_gateway_spec.rb spec/services/bookings/transition_status_spec.rb spec/services/bookings/retroactive_checkin_spec.rb
```

Results:

```text
bundle exec rspec: 1639 examples, 0 failures
RuboCop: no offenses detected
```

## Acceptance Criteria Status

Completed:

1. Central folio transaction creation is guarded.
2. Normal staff postings are blocked during `audit_running`.
3. Normal staff postings are blocked during `audit_blocked`.
4. Normal postings are blocked for `closed` and `force_closed` dates.
5. Night audit postings are allowed during `audit_running`.
6. No-show audit postings are allowed during `audit_running`.
7. `audit_blocked` allows only blocker-resolution postings with blocker context and reason.
8. Closed/reopened date override requires permission and reason.
9. Checkout is blocked on restricted business dates.
10. Existing night audit flow still posts nightly and no-show charges.
11. Existing open-day folio posting still works.
12. Full test suite passes.

## Deferred Work

Milestone B does not implement:

1. Full financial audit-event ledger.
2. Manager approval workflows.
3. UI for audit blocker-resolution actions.
4. Reopen or force-close workflows.
5. Financial report refactors.
6. Accounting/GL export controls.

These belong to later financial and night audit milestones.
