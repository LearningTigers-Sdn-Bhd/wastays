# Milestone A: Business-Date State

## Goal

Introduce a first-class per-hotel business-date state so night audit, financial postings, reporting, and closed-date controls stop relying only on completed `NightAudit` rows.

This milestone focuses on the state foundation only. Full posting guards, financial audit events, report refactors, reopen UI, force-close UI, and accounting/GL work belong to later milestones.

## Scope

Milestone A should deliver:

1. `HotelBusinessDate` model and table.
2. A business-date state machine.
3. One business-date record per hotel/date.
4. Automatic migration backfill from existing completed night audits.
5. Automatic migration creation of open current business-date rows for hotels.
6. Night audit transition into `audit_running` when audit execution starts.
7. Night audit transition into `audit_blocked` when blockers prevent close.
8. Night audit transition into `closed` when audit completes successfully.
9. Basic posting-state query helpers for later posting guard work.
10. Specs for state transitions, uniqueness, backfill assumptions, and night audit integration.

Out of scope for Milestone A:

1. Full `FinancialControls::PostingGuard` enforcement.
2. Full financial audit-event system.
3. Reopen workflow UI.
4. Force-close workflow UI.
5. Report refactors.
6. GL/accounting export work.

## Business-Date States

Use these states:

```text
open
audit_running
audit_blocked
closed
reopened
force_closed
```

Milestone A should implement the core transitions first:

```text
open -> audit_running
audit_running -> audit_blocked
audit_running -> closed
```

`reopened` and `force_closed` can exist in the enum now, but the full workflows should be implemented in later milestones.

## Proposed Table

Create `hotel_business_dates`.

Minimum fields for Milestone A:

```text
hotel_id
business_date
status
opened_at
audit_started_at
blocked_at
closed_at
blockers_snapshot
created_at
updated_at
```

Fields to add now if useful for future workflows:

```text
reopened_at
force_closed_at
closed_by_id
reopened_by_id
force_closed_by_id
reopen_reason
force_close_reason
```

Recommended approach: keep the first migration focused on the minimum fields unless upcoming reopen/force-close work is expected immediately.

## Indexes And Constraints

Add these indexes:

```text
unique index on [hotel_id, business_date]
index on [hotel_id, status]
index on [hotel_id, business_date, status]
```

Reasons:

1. Prevent duplicate business-date rows for a hotel/date.
2. Support fast lookup by hotel/date.
3. Support operational screens and scheduled audit jobs.

## Migration Backfill

Because this is a new feature, the migration should backfill automatically.

The migration should:

1. Create `hotel_business_dates`.
2. Add indexes and uniqueness constraints.
3. Backfill `closed` rows from completed `night_audits`.
4. Backfill `open` current business-date rows for hotels that do not already have a row for their current business date.

Backfill rules for completed night audits:

```text
hotel_id: night_audit.hotel_id
business_date: night_audit business/audit date
status: closed
opened_at: night_audit.created_at if available
closed_at: night_audit.completed_at if available, otherwise night_audit.updated_at
blockers_snapshot: nil
```

Backfill rules for current hotel business dates:

```text
hotel_id: hotel.id
business_date: hotel.current_business_date / existing business-date calculation
status: open
opened_at: current time
```

If a hotel already has a `closed` row for the current business date, do not create an `open` row for that same date.

Implementation notes:

1. Use `upsert_all` or idempotent insert logic where practical.
2. Rely on the unique `[hotel_id, business_date]` index for correctness.
3. Avoid duplicate rows during migration retry.
4. Prefer the existing hotel business-date calculation if this application is not constrained by strict long-term migration compatibility.

## Model Responsibilities

`HotelBusinessDate` should own:

1. Status enum.
2. Valid state transitions.
3. Timestamp assignment for transitions.
4. Blocker snapshot storage.
5. Posting-state helper methods.

Suggested methods:

```ruby
start_audit!
block_audit!(blockers:)
complete_audit!
retry_audit!
closed_or_locked?
normal_posting_allowed?
audit_posting_allowed?
```

Milestone A transition rules:

```text
start_audit!: allowed from open, audit_blocked, reopened
block_audit!: allowed only from audit_running
complete_audit!: allowed only from audit_running
retry_audit!: allowed only from audit_blocked
```

Posting helper behavior:

```text
open: normal postings allowed
audit_running: only audit-owned postings allowed
audit_blocked: normal postings blocked
closed: normal postings blocked
reopened: controlled correction postings allowed later
force_closed: normal postings blocked
```

## Night Audit Integration

Update night audit execution so the business date is claimed and tracked explicitly.

Recommended flow:

1. Find or create `HotelBusinessDate` for the hotel/date.
2. Lock the business-date row.
3. Transition `open -> audit_running`, or `audit_blocked -> audit_running` for retry.
4. Run pre-close blocker evaluation.
5. If pre-close blockers exist, store the blocker snapshot and transition `audit_running -> audit_blocked`.
6. If no pre-close blockers exist, continue no-show and nightly charge posting.
7. Run post-close blocker evaluation.
8. If post-close blockers exist, store the blocker snapshot and transition `audit_running -> audit_blocked`.
9. If successful, transition `audit_running -> closed`.

The existing `NightAudit` row should continue to reflect its own workflow status, but the business-date row becomes the source of truth for whether the hotel/date is open, running, blocked, or closed.

## Locking Strategy

The implementation should prevent duplicate audit runners for the same hotel/date.

Recommended approach:

1. Use a database row lock on the `HotelBusinessDate` record when claiming audit execution.
2. Move the state to `audit_running` before posting no-shows or nightly charges.
3. Refuse a second runner when the state is already `audit_running`.
4. Keep transaction-posting idempotency in place for defense in depth.

If the audit execution is entirely local database work, holding a lock across the core run may be acceptable. If future audit execution includes external calls or long-running operations, use a short lock to claim the date, then rely on `audit_running` state to block duplicate runners.

## Closed-Date Source Of Truth

Milestone A should introduce:

```ruby
HotelBusinessDate.closed_for?(hotel:, date:)
```

During this milestone, existing `NightAudit.closed_for_date?` callers can either remain unchanged or delegate to `HotelBusinessDate.closed_for?` if low-risk.

Recommended behavior during transition:

1. Prefer `HotelBusinessDate.closed_for?` for new code.
2. Preserve compatibility for any existing callers of `NightAudit.closed_for_date?`.
3. Replace old closed-date checks in Milestone B when the posting guard is introduced.

## Test Plan

Add model specs for `HotelBusinessDate`:

1. Requires `hotel_id`.
2. Requires `business_date`.
3. Enforces unique `[hotel_id, business_date]`.
4. Defaults to `open`.
5. `start_audit!` transitions `open -> audit_running`.
6. `start_audit!` transitions `audit_blocked -> audit_running`.
7. `block_audit!` transitions `audit_running -> audit_blocked`.
8. `block_audit!` stores `blockers_snapshot`.
9. `complete_audit!` transitions `audit_running -> closed`.
10. Invalid transitions fail clearly.
11. `normal_posting_allowed?` is true only for `open`.
12. `audit_posting_allowed?` is true only for `audit_running`.

Add night audit specs:

1. Audit with pre-close blockers moves business date to `audit_blocked`.
2. Audit with post-close blockers moves business date to `audit_blocked`.
3. Successful audit moves business date to `closed`.
4. Retry from `audit_blocked` can move back to `audit_running`.
5. Duplicate runners cannot both claim the same business date.
6. Failed audit does not incorrectly mark the business date as `closed`.

Add migration/backfill specs if the project has migration-spec coverage. Otherwise, verify locally after migration using seed/test data.

## Acceptance Criteria

Milestone A is complete when:

1. Every hotel/date can have exactly one `HotelBusinessDate`.
2. Completed historical night audits are backfilled as `closed` business dates.
3. Every hotel has an `open` current business-date row unless that date is already closed.
4. Night audit execution transitions the business date through `audit_running`.
5. Blocked audits leave the business date in `audit_blocked`.
6. Successful audits leave the business date in `closed`.
7. A clear API exists for checking whether normal posting or audit posting is allowed.
8. Existing night audit behavior still works.
9. Specs cover valid transitions, invalid transitions, uniqueness, and basic night audit integration.

## Mechanism Explanation

The mechanism is a stateful control record per hotel and business date.

Today, closed-date behavior can be inferred from completed `NightAudit` records. That works for simple cases, but it leaves unclear states when an audit starts, blocks, fails, or partially completes. `HotelBusinessDate` makes those states explicit.

When the hotel is operating normally, the business date is `open`. Normal financial activity can continue.

When night audit starts, the date moves to `audit_running`. This claims the date for audit execution and prevents another audit runner from processing the same hotel/date. Later milestones will use this state to block normal staff postings while allowing audit-owned postings.

If audit blockers are found, the date moves to `audit_blocked`. This is safer than leaving the date `open`, because it shows that close was attempted and failed. Staff and managers can then resolve blockers or use a controlled later workflow such as force-close.

If audit completes successfully, the date moves to `closed`. This gives the application a direct source of truth for closed-date checks instead of asking whether a completed night audit exists.

The migration backfill gives existing data an initial state. Completed night audits become `closed` business dates, and each hotel gets an `open` row for its current business date unless that date is already closed. This lets the new state model start from the existing production shape without requiring a manual setup task.
