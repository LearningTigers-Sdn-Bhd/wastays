# Booking, Group Booking, Billing, and Folio Redesign

## Status

Research and implementation-planning document. This document describes the agreed target architecture and phased delivery plan. It does not authorize or contain implementation changes.

The conclusions here are based on the application code, schema, services, views, and tests rather than `docs/`.

## Agreed decisions

1. A booking represents one operational room stay.
2. Booking guests retain stay-time identity and contact snapshots while linking to a reusable guest profile.
3. Bookings in the same group may have different arrival and departure dates.
4. A child-booking edit never mutates group configuration. A local billing exception affects only that booking.
5. Changing billing or routing requires confirmation between:
   - moving existing eligible charges and routing future charges; or
   - routing future charges only.
   The first option is selected by default.
6. Group folios will not be consolidated. Each booking retains its own guest and corporate folios. Group consolidation is a presentation and reporting concern.
7. Tourism tax remains the guest's responsibility by default.
8. Advance booking deposits are received and managed at group level, then allocated to child bookings. Security deposits remain booking-level.
9. A group may have multiple corporate payers.
10. Restricted corporate credit blocks City Ledger settlement unless an authorized user overrides it or selects another settlement method.

## Core domain boundaries

```text
GROUP_BOOKING
|
+-- many BOOKINGS
|   +-- one operational room stay
|   +-- one primary BookingGuest
|   +-- zero or more additional BookingGuests
|   +-- one physical BookingRoom after assignment
|   +-- booking billing assignments
|   +-- one or more BookingFolios
|   +-- folio routing rules
|   `-- booking-level security deposits
|
+-- many GROUP_BILLING_ARRANGEMENTS
|   +-- payer and corporate account
|   +-- settlement terms
|   `-- charge-coverage defaults
|
+-- many GROUP_DEPOSITS
|   +-- one actual receipt per deposit
|   `-- many allocations into child booking folios
|
`-- group presentation and reporting
    +-- totals across child folios
    +-- payer summaries
    `-- outstanding balances
```

## Required invariants

### Booking

- A booking belongs to one hotel.
- A booking belongs to zero or one group booking.
- A booking represents one operational room stay, not a quantity of interchangeable rooms.
- A confirmed booking has one physical booking-room record with quantity equal to one.
- A booking has exactly one primary guest before check-in.
- A booking may have zero or more additional guests.
- A booking has one billing configuration of its own or resolves billing from group arrangements.
- Child changes cannot mutate group defaults.

### Booking guest

- Only one primary booking guest may exist per booking.
- The same guest cannot be linked to the same booking twice.
- The reusable `Guest` record represents the person.
- `BookingGuest` snapshots represent the identity and contact information used for that stay.
- Updating a reusable guest does not silently rewrite historical bookings.
- Updating a booking snapshot may explicitly offer to update the reusable guest profile.

### Folio and routing

- Every posted charge belongs to a concrete child booking folio.
- A group view may aggregate folios but does not become an accounting ledger.
- A corporate folio is ensured idempotently when effective billing selects a company.
- Creating a corporate folio and routing charges to it are separate operations.
- Existing postings are never rewritten in place when routing changes.
- Moving existing charges creates auditable transfer or split transactions retaining their origin.
- Tourism tax routes to the guest folio unless an explicit future policy changes that decision.

### Deposits

- Advance booking payments and refundable security deposits remain separate concepts.
- Group advance deposits are received once and must not be counted again as new cash when allocated.
- Active allocations cannot exceed the available group deposit.
- A deposit from one payer cannot automatically settle bookings assigned to another payer.
- Security deposits remain attached to the child booking and are released or forfeited through that booking's checkout.

## Target data model

### New tables

#### `group_bookings`

Proposed responsibilities:

- hotel ownership;
- group reference and name;
- organizer/contact guest;
- source and external reference;
- status;
- shared notes and metadata; and
- optional default dates used only as creation defaults.

Different child bookings may retain different stay dates.

#### `group_billing_arrangements`

A group has many arrangements so multiple companies or payers can participate.

Proposed responsibilities:

- `group_booking_id`;
- arrangement name;
- payer type;
- hotel corporate account;
- settlement type;
- preferred payment method;
- billing, purchase-order, and authorization references;
- validity dates;
- status; and
- default charge-coverage policy.

#### `booking_billing_assignments`

Proposed responsibilities:

- assign a booking or charge category to a group billing arrangement;
- record booking-local exceptions;
- identify the effective payer for corporate folio creation; and
- prevent child changes from mutating the parent arrangement.

Depending on the final routing design, one booking may have several assignments by charge category.

#### `group_deposits`

Represents an actual advance payment received for a group.

Proposed responsibilities:

- group booking and hotel;
- payer or corporate account;
- amount and currency;
- payment method and external reference;
- received timestamp;
- lifecycle status;
- refund information; and
- immutable receipt/audit metadata.

#### `group_deposit_allocations`

Represents movement of group deposit liability into a child booking folio.

Proposed responsibilities:

- group deposit;
- child booking and booking folio;
- amount;
- allocation timestamp and actor;
- linked folio transaction;
- reversal lineage; and
- allocation status.

Allocation is not a second cash receipt.

### Modified tables

#### `bookings`

- Add optional `group_booking_id`.
- Remove the meaning of “group booking” derived from room quantity.
- Clarify whether legacy `guest_*` columns are temporary snapshots or are retired after migration.
- Keep independent dates, status, totals, and operational lifecycle.

#### `booking_rooms`

- One confirmed row represents one room stay.
- Enforce quantity equal to one for confirmed bookings.
- Expand aggregated quote quantities into individual bookings during confirmation.
- Review whether room moves require a separate assignment-history model.

#### `booking_guests`

- Replace or supplement `is_primary` with an explicit role.
- Add stay-time snapshots where required.
- Add database enforcement for one primary guest per booking.
- Add uniqueness for `(booking_id, guest_id)`.

#### `booking_folios`

- Continue belonging to a concrete child booking.
- Support guest and one or more corporate payer folios.
- Ensure corporate folios idempotently by booking and payer.
- Do not add group-master folio ownership.

#### `folio_routing_rules`

- Resolve group billing intent to concrete child folios.
- Support group-derived rules and booking-local exceptions.
- Support effective dates and charge-code coverage.
- Preserve the source of inherited rules.
- Support confirmation-controlled application to existing postings.

### Financial and operational tables requiring review

- `folio_transactions`
- `folio_forecasted_charges`
- `folio_operation_logs`
- `financial_audit_events`
- `deposits`
- `payment_transactions`
- `refund_requests`
- `ar_invoices`
- `journal_batch_entries`
- `booking_audit_logs`

Services and reports that assume `booking.booking_rooms.first` must also be inventoried and corrected.

## Deposit model: current and target behavior

### Current advance booking payments

Advance booking payments currently appear as `FolioTransaction` records with:

```text
transaction_type = payment
category         = booking_payment
```

Deposit liability is inferred from booking-payment transactions, earned charges, and refunds. There is no explicit advance-deposit record for an individual booking.

### Current security deposits

The existing `deposits` table represents refundable security deposits only. They are collected during check-in, held outside ordinary folio transactions, and released or forfeited through child-booking checkout.

### Target group advance-deposit flow

```text
Receive MYR 10,000 once
|
`-- GroupDeposit: MYR 10,000
    +-- Allocate Booking 101 / ABC Folio: MYR 2,000
    +-- Allocate Booking 102 / ABC Folio: MYR 1,500
    +-- Allocate Booking 103 / XYZ Folio: MYR 1,000
    `-- Unallocated: MYR 5,500
```

Allocation strategies may include:

- manual allocation;
- allocation by outstanding balance;
- proportional allocation; and
- allocation restricted to bookings covered by the deposit payer.

The default should retain an unallocated balance until staff intentionally allocates it or a controlled settlement workflow allocates it.

## Billing and routing behavior

### Effective billing

```text
Group billing arrangement
        |
        `-- booking assignment
              +-- inherited charge responsibility
              `-- optional local exception
```

A local exception affects only its booking. Group-level actions are the only actions allowed to update or propagate group configuration.

### Corporate folio creation

When effective billing selects a company:

1. Validate the hotel's corporate account.
2. Ensure the appropriate booking corporate folio exists.
3. Configure the company as its payer.
4. Apply explicit routing rules.
5. Preserve the guest folio for tourism tax and uncovered charges.

Saving billing preferences repeatedly must not create duplicate corporate folios.

### Routing-change confirmation

When changed routing affects posted charges, show the number and total of eligible existing transactions and require one choice:

```text
(selected) Move existing eligible charges and route future charges
(         ) Route future charges only
```

The first choice is selected by default but is never performed without confirmation.

Moving existing charges must use normal folio transfer/split machinery and retain:

- original booking and folio;
- original transaction;
- destination folio and resulting transaction;
- routing rule;
- actor, timestamp, and reason; and
- reversal lineage when undone.

### Corporate-credit restriction

When a corporate account becomes unavailable or exceeds permitted credit:

- retain existing charges and visible routing instructions;
- flag all affected bookings;
- block City Ledger settlement by default;
- allow an authorized override with an audit reason; or
- require another approved account or settlement method.

The system must not silently make the guest responsible for corporate charges.

## Control-panel layout principles

The workspace must declare a layout mode per tab:

```text
center_only
left_and_center
center_and_right
left_center_right
```

A column appears only when it controls or materially explains the center content.

Recommended layouts:

| Tab | Layout |
| --- | --- |
| Booking Details | Center only |
| Room & Rate (standalone booking) | Center only |
| Room & Rate (group scope) | Child-booking selector + center |
| Guest Details | Guest selector + center |
| Folio Operations | Folio selector + center |
| Billing Preferences | Group/booking scope + center |
| Source Details | Center only |
| Housekeeping Requests | Request/room scope + center |
| Audit Trails | Audit scope + center |

The generic right-side summary should be removed where it merely repeats global booking information.

### Room, rate, and financial responsibility

The existing **Room Charges** tab should be renamed **Room & Rate**. Its responsibility is the commercial and operational definition of the stay:

- stay dates and night count;
- room type and physical room assignment;
- occupancy;
- rate plan, nightly rates, and estimated stay value;
- room moves and effective dates; and
- room/rate assignment history.

It must not act as a transaction ledger. Posted room charges, adjustments, payments, transfers, and refunds belong in **Folio Operations**. **Billing Preferences** determines who is responsible and where eligible future charges route.

```text
Room & Rate
`-- what room is being sold and at what rate?

Billing Preferences
`-- who is responsible for each charge category?

Folio Operations
`-- what was actually posted, transferred, paid, or refunded?
```

At group scope, **Room & Rate** uses the left rail to select one child booking and the center panel to display that booking's room and rate. Each child represents one room stay:

```text
+------------------------+--------------------------------------------------+
| CHILD BOOKINGS         | SELECTED BOOKING: B-10031                       |
|                        |                                                  |
| > B-10031 / Family 01  | Stay:       12-15 Aug, 3 nights                 |
|   Dr Isaac / RM 700    | Room type:  Family Room                         |
|                        | Room:       Family Room 01                       |
|   B-10032 / Family 02  | Rate plan:  Corporate Flexible                  |
|   Nursakinah / RM 700  | Nightly:    RM 700                              |
|                        |                                                  |
|   B-10033 / Deluxe 08  |                 [Change room] [Change rate]      |
|   Amir / RM 520        |                                                  |
+------------------------+--------------------------------------------------+
```

At standalone-booking scope, the left rail is hidden because there is no sibling booking to select. The center content uses the full width. A temporary right editor may appear while changing a room or rate, but it is not permanently displayed.

A room or rate edit affects only the selected child booking. Applying a rate plan or other change across multiple children requires a separate explicit bulk group action with selected bookings and a change preview.

If a rate change overlaps already-posted nights, confirmation must distinguish:

1. adjust eligible existing postings and future postings; or
2. apply only to future unposted nights.

Any adjustment to an existing posting must retain its original transaction and audit lineage.

## Group financial presentation

No consolidated group ledger or master folio will be introduced. The group workspace and reports will aggregate child records for presentation:

```text
Group summary
+-- total charges
+-- total payments
+-- total outstanding
+-- group deposits: received, allocated, and unallocated
+-- balances by booking
+-- balances by room
+-- balances by guest
+-- balances by corporate payer
`-- folio and settlement statuses
```

Reports may visually resemble consolidated statements but must list the underlying booking and folio references.

# Delivery phases

## Phase 0: Baseline and invariant specification

### Work

- Inventory every service, presenter, controller, report, and job that assumes the first booking room.
- Inventory all code paths that read or write booking `guest_*` fields and `BookingGuest` records.
- Inventory folio creation, posting, routing, transfers, payment synchronization, deposits, refunds, invoices, checkout, and night-audit effects.
- Define status and financial invariants as executable specifications before structural migration.
- Identify existing data that violates the target invariants.

### Exit criteria

- A reviewed dependency map exists.
- Data-quality queries identify multi-room, duplicate-primary, missing-primary, and inconsistent-guest records.
- Existing financial behavior is covered by characterization tests.
- Migration rollback and reconciliation strategies are documented.

## Phase 1: Stabilize the single-booking domain

### Work

- Make primary-guest selection deterministic.
- Add uniqueness and primary-guest constraints after repairing existing data.
- Introduce booking-guest snapshots and explicit update behavior.
- Remove operational reliance on aggregated booking-room quantity.
- Replace first-room assumptions with the one-room-stay invariant.
- Preserve quote-level room quantities before confirmation.
- Confirm inventory, rates, forecasts, folios, check-in, checkout, cancellation, and reporting for one booking/one room.

### Exit criteria

- Every confirmed booking operates exactly one room stay.
- A booking has one enforceable primary guest.
- Additional guests belong unambiguously to that booking.
- Existing single-booking lifecycle and financial tests pass.
- Multi-room quantities cannot enter the confirmed operational model.

## Phase 2: Introduce group bookings

### Work

- Add `group_bookings` and optional booking membership.
- Add group references, organizer/contact, source, status, notes, and metadata.
- Build group creation that expands requested rooms into child bookings.
- Permit independent child dates and statuses.
- Add group membership, cancellation, and child-removal audit behavior.
- Define group status as a projection of child states or as a separately controlled coordination status.

### Exit criteria

- A group can create and coordinate several independent room bookings.
- Child changes never silently mutate group data.
- Each child remains usable through existing booking lifecycle workflows.
- Group membership and lifecycle changes are audited.

## Phase 3: Billing arrangements and corporate folios

### Work

- Add multiple group billing arrangements.
- Add booking billing assignments and booking-local exceptions.
- Resolve effective payer and coverage per booking and charge category.
- Ensure booking corporate folios idempotently.
- Retain guest folios for tourism tax and uncovered expenses.
- Add corporate-account eligibility and credit checks.
- Block restricted City Ledger settlement with authorized override support.

### Exit criteria

- One group can use multiple corporate payers.
- Each booking resolves an unambiguous payer per covered charge category.
- Repeated saves do not duplicate corporate folios.
- Tourism tax remains on the guest folio by default.
- Restricted corporate settlement cannot proceed without approved handling.

## Phase 4: Routing inheritance and existing-charge application

### Work

- Add group-derived routing intent and booking-local routing exceptions.
- Resolve routing to concrete child booking folios.
- Add charge-code, date-range, and optional amount/percentage coverage where required.
- Add confirmation between existing-and-future versus future-only application.
- Preview the count and value of affected existing transactions.
- Apply existing-charge changes using audited transfer and split operations.
- Support reversal without losing transaction lineage.

### Exit criteria

- Future postings route deterministically.
- Existing postings move only after explicit confirmation.
- Original transaction provenance remains intact.
- Group changes propagate only through an explicit group action.
- Child exceptions do not mutate group arrangements.

## Phase 5: Group advance deposits and allocation

### Work

- Add group deposit receipt and allocation records.
- Associate each group deposit with its actual payer.
- Record one cash receipt and prevent duplicate recognition during allocation.
- Allocate deposits to concrete child booking folios.
- Support manual, balance-based, proportional, and payer-restricted allocation.
- Support allocation reversal, unallocated refunds, and cancellation handling.
- Update deposit-liability reporting to include group receipts and allocations without double-counting.
- Keep security-deposit collection and release at child-booking level.

### Exit criteria

- Group deposit receipt, allocation, reversal, and refund reconcile exactly.
- Allocations cannot exceed the available amount.
- Cross-payer allocation is prevented unless explicitly authorized by policy.
- Booking folios show allocated credits with group-deposit provenance.
- Deposit-liability and GL reports do not double-count receipts and allocations.
- Security-deposit behavior remains unchanged for child bookings.

## Phase 6: Booking control-panel redesign

### Work

- Replace implicit rail behavior with declared tab layout modes.
- Rename Room Charges to Room & Rate and remove financial-ledger behavior from it.
- Make Booking Details center-only.
- Make Room & Rate center-only for standalone bookings.
- Give group-scoped Room & Rate a child-booking selector whose selection controls the center content.
- Support room type, physical-room assignment, rate plan, nightly rate, effective date, and assignment history in Room & Rate.
- Keep posted charges, adjustments, transfers, payments, and refunds in Folio Operations.
- Give Guest Details a functional guest selector.
- Give Folio Operations a functional folio selector.
- Build Billing Preferences with group and child-booking scope selection.
- Remove generic context panels that repeat global summaries.
- Ensure selectors actually scope center content and URL state.
- Add routing-change previews and confirmations.

### Exit criteria

- Every visible column has a defined purpose.
- Selecting a left-rail record changes the center content.
- Tabs with no secondary scope use the available width.
- Each Room & Rate edit affects only the selected child unless staff invoke an explicit bulk group action.
- Rate changes show their estimated and posted-charge impact before confirmation.
- Existing room-charge postings are adjusted only through auditable folio transactions.
- Billing scope clearly distinguishes group arrangements from booking-local exceptions.
- System tests cover direct links, Turbo navigation, and layout modes.

## Phase 7: Group workspace and reporting

### Work

- Build group operational and financial summaries across child bookings.
- Add views grouped by booking, room, guest, payer, folio status, and balance.
- Present separate child folios as a coherent group statement without merging ledgers.
- Add deposit-received, allocated, unallocated, and refunded summaries.
- Add exportable group statements that retain child booking and folio references.
- Add exception views for credit restrictions, routing failures, missing guests, and unsettled balances.

### Exit criteria

- Staff can understand the entire group without opening every booking.
- Every displayed total reconciles to child folios and group deposit records.
- Reports retain booking, payer, and folio-level traceability.
- No group master folio or hidden consolidated ledger exists.

## Phase 8: Migration, rollout, and cleanup

### Work

- Migrate legacy multi-room bookings into groups with child bookings.
- Split room quantities into one-room child bookings.
- Assign guests, folios, payments, charges, forecasts, and deposits using reviewed rules.
- Quarantine ambiguous records for manual reconciliation rather than guessing.
- Run old and new financial reconciliation reports in parallel.
- Introduce feature gates and staged hotel rollout.
- Remove legacy group detection and obsolete fallback behavior only after reconciliation.

### Exit criteria

- Migrated bookings reconcile operationally and financially.
- No payment, charge, deposit, refund, or invoice is orphaned or duplicated.
- Ambiguous migrations are resolved and auditable.
- Legacy multi-room and guest fallback paths are removed.
- Rollout monitoring shows stable night-audit, checkout, reporting, and ledger behavior.

## Cross-phase validation requirements

Every phase that changes financial behavior must verify:

- transaction immutability and lineage;
- hotel and currency consistency;
- night-audit and closed-business-date rules;
- idempotency under retries;
- database constraints and concurrent writes;
- audit actor, reason, and timestamps;
- deposit-liability and general-ledger reconciliation;
- cancellation, no-show, reinstatement, room move, early checkout, and refund behavior; and
- permission enforcement for posting, routing, transferring, overriding credit, and refunding.

## Explicitly out of scope for the initial redesign

- A consolidated group/master folio.
- A billing-only synthetic booking.
- Silent reassignment of corporate charges to guests.
- Automatic movement of existing charges without confirmation.
- Combining advance booking deposits with refundable security deposits.
- Treating a confirmed `BookingRoom.quantity > 1` as several physical rooms.
