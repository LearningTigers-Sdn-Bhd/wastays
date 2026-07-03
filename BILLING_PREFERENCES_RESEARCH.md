# Billing Preferences, Folio Windows, Routing, and Tax Inclusions

## Status and scope

This document compiles the current product discussion and code research for:

- single- and group-booking billing preferences;
- billing-party management;
- folio-window creation;
- transaction-code routing;
- booking-only and hotel-wide tax inclusions; and
- the Folio Operations area of the booking control panel.

It is a research and target-behavior document. It does not authorize or contain application-code changes.

`BOOKING_GROUP_REDESIGN_PHASES.md` is used only to identify the relevant delivery phases:

- Phase 3: billing arrangements and corporate folios;
- Phase 4: routing inheritance and existing-charge application; and
- Phase 6: booking control-panel redesign.

All current-state findings in this document are based on the live application code, schema, services, views, and tests rather than `docs/`.

## Agreed product decisions

1. Billing Preferences is the source of billing intent: who may be billed and where transaction codes should route.
2. Every guest attached to a single or child booking automatically becomes an available billing party.
3. Companies, government accounts, and agencies are added explicitly. Other billing contacts are deferred from the first release.
4. A billing party may own multiple folio windows within the same booking.
5. Creating an additional folio for a billing party does not silently change any routing.
6. Folio windows are created in Folio Operations by selecting a billing party in the `Sharer / Billing party` field.
7. Billing Instructions shows one combined operational table. Defaults and custom routing rules are not separated.
8. The table has no Status column and no Action column.
9. Every routable parent transaction code, whether system-defined or custom, appears exactly once. Non-routable payment and system-control codes are excluded.
10. Tax and inclusion-generated transaction codes do not appear as top-level rows.
11. Every parent transaction-code row is collapsible, including rows with no attached taxes or charges.
12. Each parent row has a Tax inclusions summary column.
13. Attached taxes and charges are managed inside the expanded content and may have booking-specific routing exceptions.
14. Routing is edited inline by changing the Target folio cell into a dropdown with cancel and confirm controls.
15. A routing change affecting eligible posted charges requires a preview and an explicit choice between moving existing eligible charges or routing upcoming charges only.
16. Folio Operations keeps its existing left rail and booking/folio hierarchy.
17. Folio Operations has no Ledger, Forecast, or Activity tabs. Its center area presents posting actions followed by the posted ledger.
18. Activity belongs in Audit Trails. Forecasts do not appear as a separate Folio Operations tab; upcoming items are available in a collapsed expandable section.
19. Group views never create a consolidated group/master folio. Every ledger remains attached to a concrete child booking.

## Domain vocabulary

The UI and domain should keep four concepts distinct:

```text
BILLING PARTY
Who may receive or be responsible for a bill
Guest | Company/Government | Agency

        |
        v

FOLIO WINDOW
A concrete ledger belonging to one booking and one billing party

        |
        v

ROUTING
The concrete folio that receives a transaction code

        |
        v

SETTLEMENT
How the folio is paid, closed, or transferred to City Ledger
```

Selecting a billing party does not itself mean that all transaction codes route to that party. Creating a folio also does not change routing unless staff explicitly edit Billing Instructions.

## Billing parties

### Supported party types

```text
Booking guests
Company / Government accounts
Travel agencies (deferred until a hotel-scoped agency account exists)
```

The first billing-party release supports booking guests and company/government accounts. The source of a booking is not sufficient proof that an agency is financially responsible. Agency billing should use a proper hotel-scoped agency account or equivalent explicit billing identity, so agency billing is deferred until that domain exists. `Other billing contact` is also deferred and can later be introduced as a booking-scoped snapshot if operational demand justifies it.

### Automatic guest participation

```text
Add guest to booking
        |
        v
BookingGuest created
        |
        v
Guest appears in Billing Preferences
        |
        v
Guest becomes selectable in Add Folio Window
```

Rules:

- All current booking guests are available billing parties.
- Changing the primary guest changes the displayed role but does not rewrite existing folios or routing.
- For a group, each guest belongs to the relevant child booking's billing-party list.
- A group overview may aggregate child guests for presentation but does not make them group-wide payers automatically.
- A non-staying organizer or group payer must be added explicitly.
- Removing a guest who already owns a folio, routing rule, or posted transaction must not destroy financial identity. The system must preserve a snapshot and require reassignment where appropriate.

### Billing Preferences presentation

```text
BILLING PREFERENCES
Booking BK-10428

Billing parties                                      [+ Add billing party]

+----------------------------------------------------------------------------+
| Guest | Aina Rahman                         Cash / card                Edit |
| Primary guest                                                              |
+----------------------------------------------------------------------------+
| Company | Acme Engineering Sdn Bhd          City Ledger               Edit |
| PO AC-2026-774 | Direct bill enabled                                     |
+----------------------------------------------------------------------------+
```

The Add billing party action is for companies and government accounts in the first release. Guests become billing parties only by being attached to the selected booking, so they do not require a second add action. Agencies should be added later only after a hotel-scoped agency account model exists.

## Folio-window creation

### Relationship

One billing party may own many folio windows:

```text
Aina Rahman
+-- Guest Folio F01
`-- Incidentals Folio F02

Acme Engineering
`-- Accommodation Folio F03
```

There must not be a uniqueness rule limiting a booking and billing party to one folio.

### Creation interface

```text
ADD FOLIO WINDOW

Sharer / Billing party
[ Aina Rahman - Guest                                  v ]

Folio name
[ Incidentals Folio                                      ]

Currency
[ MYR                                                    ]

                                          [Cancel] [Create folio]
```

The selector is grouped by party type:

```text
Guests
  Aina Rahman
  Daniel Lee

Companies / Government
  Acme Engineering
  Sabah State Department

Agencies
  Sabah Holidays
```

`Sharer / Billing party` is preferable to `Sharer` alone because companies and agencies are not room sharers in the usual hotel meaning.

### Creation invariant

```text
Before: ROOM -> Aina F01
Create: Aina F02
After:  ROOM -> Aina F01   (unchanged)
```

The new folio becomes available in the routing dropdown but receives no transaction codes automatically unless an explicitly defined preference says otherwise.

## Billing Instructions

### Booking Control Panel implementation decision (2026-07-03)

The Booking Control Panel no longer embeds an “Advanced Billing Rules” disclosure in Billing Preferences. For a concrete booking, authorized staff use **Change Billing Routes** from the left rail. It opens one wide, staged offcanvas containing the effective research table with Billing party before Target folio. Target folios are constrained to the selected party. All edits—including booking-local tax inclusions—are submitted through one footer **Apply changes** action. When posted charges are affected, the system presents one combined impact review and one global existing-and-future or future-only choice.

Every routable parent row is expandable. Attached taxes and charges render as a flush nested table with aligned borders and no padded card container; an empty parent still expands to an explicit empty state. Hotel-default tax inclusion changes remain outside this booking-local flow.

### Main table

Billing Instructions contains every active, routable parent transaction code, including system and custom codes. Non-routable payment and system-control codes are excluded rather than displayed as locked rows. A tax or charge code created solely as the posting result of an inclusion is also excluded from the top-level list and appears under its parent.

The routability rule must be defined centrally and used consistently by the presenter, routing command, and tests. At minimum, a row is eligible only when the code can resolve an automatic future posting to a concrete folio. Codes whose destination is always selected manually, inherited from an originating transaction, or controlled exclusively by the system are not Billing Instructions.

```text
+---+----------+----------------------+-----------------------+------------------------+
|   | Code     | Transaction          | Tax inclusions        | Target folio           |
+---+----------+----------------------+-----------------------+------------------------+
| > | ROOM     | Room charge          | 2 attached            | Acme F03            [p]|
| > | MINIBAR  | Minibar              | None                  | Aina F01            [p]|
| > | LAUNDRY  | Laundry              | Service charge        | Aina F02            [p]|
+---+----------+----------------------+-----------------------+------------------------+

[p] = pencil icon
```

System/custom provenance may appear as quiet secondary text beneath the code. It is not a separate status column.

Archived transaction codes are historical configuration and should not appear in the operational table.

### Inline routing edit

```text
| ROOM | Room charge | 2 attached | [ Acme F03 v ]  [x] [check] |
```

Behavior:

1. Pencil changes only the Target folio cell into a dropdown.
2. Cancel restores the previous effective target without mutation.
3. Confirm asks the server for an impact preview before committing.
4. If no existing eligible charges are affected, the routing change saves directly.
5. If posted charges are affected, the warning dialog is shown.
6. Saving the rule and applying selected existing-charge movements should be one controlled, auditable operation.

### Routing warning

```text
CHANGE TARGET FOLIO?

ROOM will change:
Aina F01 -> Acme F03

12 existing eligible charges | MYR 4,860.00

(*) Move existing eligible charges to F03 and route upcoming charges to F03
( ) Leave existing charges where they are; route upcoming charges to F03 only

Reason
[ Corporate authorization received                              ]

                                      [Cancel] [Confirm change]
```

Posted transactions are moved through auditable transfer/split operations. They are never rewritten in place.

## Tax and attached-charge inclusions

### Collapsible behavior

Every parent transaction-code row is collapsible. This provides a consistent place to inspect or configure attached taxes and charges.

Expanded with attachments:

```text
| v | ROOM | Room charge | 2 attached | Acme F03 [p] |
+---------------------------------------------------------------+
| TAXES AND ATTACHED CHARGES                                   |
|                                                              |
| SST 8%       8% of room charge    Hotel default              |
|              Follows ROOM -> Acme F03                  [p] [x]|
|                                                              |
| Tourism Tax MYR 10 / night        Booking only               |
|              Guest F01                               [p] [x]|
|                                                              |
|                              [+ Include tax or charge]       |
+---------------------------------------------------------------+
```

Expanded without attachments:

```text
| v | MINIBAR | Minibar | None | Aina F01 [p] |
+------------------------------------------------+
| No taxes or charges attached.                |
|                  [+ Include tax or charge]   |
+------------------------------------------------+
```

### Routing inheritance

Attached items follow the parent target unless they have an explicit child exception:

```text
ROOM -> Acme F03
+-- SST -> follows ROOM -> Acme F03
`-- Tourism Tax -> explicit exception -> Guest F01
```

Changing the parent route updates following children. Explicit child exceptions remain unchanged and visible.

### Inclusion scope

The effective configuration is:

```text
Effective booking inclusions
    = Hotel default inclusions
    + Booking-only additions
    - Booking-only exclusions
```

Removal semantics:

- Removing a booking-only inclusion deletes that local addition.
- Removing a hotel default from one booking creates a booking-only exclusion.
- Removing an inclusion globally changes hotel configuration only after a hotel-scope confirmation.
- Posted transactions remain untouched.
- Upcoming forecasts or postings are recalculated only according to an explicit reviewed policy.

### Inclusion offcanvas

```text
INCLUDE TAX OR CHARGE
MINIBAR | Minibar

Available inclusions

[x] SST 8%                       Percentage | 8%
[ ] Tourism Tax                  Flat | MYR 10
[ ] Service Charge               Percentage | 10%
[ ] Heritage Fee                 Flat | MYR 2

Apply change to

(*) This booking only
    Changes upcoming MINIBAR postings for BK-10428.

( ) Hotel default
    Changes MINIBAR defaults across the hotel.

                                      [Cancel] [Review changes]
```

Hotel-default changes require the hotel-configuration permission. Booking or folio permissions alone must not authorize them.

### Hotel-default warning

```text
CHANGE HOTEL DEFAULT?

This changes the default inclusions for MINIBAR across the hotel.

Affected:
- future bookings and postings;
- future manual postings using this transaction code; and
- existing upcoming forecasts only where the configured recalculation policy permits it.

Posted transactions will not be changed.

Reason
[                                                               ]

                            [Go back] [Apply to hotel default]
```

The impact preview must reflect the actual transaction code. Room-revenue forecasts and manually posted service codes do not necessarily share the same recalculation behavior.

For a group booking, `This booking only` means the selected child booking. Group-wide propagation should be a separate, explicit bulk action over selected child bookings.

## Folio Operations

The existing booking/folio left rail remains unchanged.

```text
+-------------------------+------------------------------------------------+
| BOOKING / FOLIOS        | AINA RAHMAN | F02                             |
|                         |                                                |
| v BK-10428              | [Add Payment] [Add Charge]                    |
|   Guest Folio | F01     | [Apply Discount] [More Actions v]             |
| > Aina Rahman | F02     |                                                |
|   Acme Company | F03    | Posted transaction ledger                     |
+-------------------------+------------------------------------------------+
```

The center area has no secondary tabs. It contains:

1. selected-folio identity, payer, status, and balance;
2. Add Payment;
3. Add Charge;
4. Apply Discount;
5. More Actions; and
6. the posted transaction ledger.

`More Actions` contains permission-dependent operations such as:

- transfer charge;
- other adjustment;
- issue refund;
- void or reverse;
- print folio; and
- close or reopen folio.

Activity belongs in Audit Trails. Forecast information is presented as a collapsed Upcoming section beneath the posted ledger, not as a tab and not mixed indistinguishably with posted accounting entries.

```text
Posted transaction ledger

> Upcoming charges | 6 items | MYR 760.00
```

Expanding Upcoming reveals forecast rows with unmistakable `Upcoming` treatment and no implication that they have posted. The section is collapsed by default.

## Single- and group-booking behavior

### Single booking

```text
Booking guests
      +
Explicit companies/agencies
      |
      v
Booking billing parties
      |
      v
One or more folios per party
      |
      v
Transaction-code routing to concrete folios
```

### Group booking

```text
Group billing arrangements
        |
        +-- selectable by child booking
        |
Child Booking A -- parties -- folios -- ledger
Child Booking B -- parties -- folios -- ledger
Child Booking C -- parties -- folios -- ledger

Group view = presentation and bulk-control surface
Group view != accounting ledger or master folio
```

A child-booking edit does not mutate a group arrangement or hotel default. Group and hotel propagation always require an explicitly scoped action.

### Guest billing boundary across child bookings

Guest billing responsibility is booking-local. A guest is available as a billing party only for bookings where that person has a `BookingGuest` record.

```text
GROUP G-100

BK-101 / Room 201
`-- Aina Rahman -> available for BK-101 folios

BK-102 / Room 202
`-- Daniel Lee -> available for BK-102 folios

Aina is not available for BK-102 unless she is added as a guest to BK-102.
```

Rules:

- A guest attached to a child booking is automatically a billing party for that child only.
- A group guest cannot be assigned directly as a guest billing party to a sibling booking.
- If the same person is legitimately attached to several child bookings, each `BookingGuest` makes that person available within its own booking.
- Companies, government accounts, and agencies may still be assigned explicitly across selected child bookings.
- Every guest folio belongs to the same booking as its `BookingGuest` billing party.
- Removing a guest cannot erase an existing folio or transaction snapshot; removal must be blocked or handled through a controlled reassignment workflow when financial references exist.

## Current implementation findings

### Billing parties and assignments

- Standalone Billing Preferences is currently inferred from existing folios rather than backed by a dedicated billing-party collection.
- `BookingBillingAssignment` requires a `GroupBillingArrangement`, so it cannot represent standalone billing parties.
- `GroupBillingArrangement` currently supports only `guest` and `company` payer types.
- `BookingFolio` supports payer strings for guest, company, agent, hotel, and custom, but only company has a concrete account association. The generic `payer_id` does not provide a safe typed relationship for guests or agencies.
- There is no complete hotel agency billing account domain in the current code.

### Folio creation

- The existing Add Folio form asks staff to choose folio type and payer type directly.
- It does not select from a unified booking billing-party list.
- A company folio can be ensured idempotently from a group arrangement, but this behavior is separate from a general multi-party folio-creation workflow.

### Assignment and routing disconnect

- Applying a group arrangement creates booking billing assignments and may ensure a corporate folio.
- That action does not itself synchronize transaction-code routing rules.
- Actual posting resolution uses an active `FolioRoutingRule` and otherwise falls back to the booking's primary folio.
- Consequently, the present application can display company responsibility while postings still resolve to the primary folio unless routing rules are separately created.

### Billing Instructions

- The presenter currently uses active charge codes as parent rows.
- Explicit rules and default rows are rendered in separate table sections.
- Status and Action columns are present.
- Only parent rows with attached taxes are currently collapsible.
- The existing rule editor is an offcanvas form rather than an inline Target folio edit.
- Existing-charge review and routing-rule editing are separate actions.

### Tax configuration

- `TransactionCodeTax` is a hotel-scoped association between a transaction code and either a primary tax key or a `HotelTax`.
- It has no booking reference or local override scope.
- The transaction-code editor replaces those hotel-wide associations when saving.
- Tax-generated transaction codes are created from hotel tax definitions and may be `tax` or `charge` kinds depending on the configured charge type.
- Room tax posting information is snapshotted into the booking financial data, so changing global attachment rules must not silently rewrite historical financial intent.
- Supporting `This booking only` requires a booking-local include/exclude override layer rather than mutating `transaction_code_taxes`.

### Folio Operations

- The control panel already has a booking/folio left rail and grouped folio hierarchy.
- The center panel currently contains Ledger, Forecast, and Activity navigation.
- Posting actions already exist but use labels such as Post Payment, Post Charge, and Post Adjustment.
- The ledger presenter can mix posted and forecasted rows, while the agreed target emphasizes posted accounting records in Folio Operations.

## Target domain implications

The eventual implementation will need explicit concepts equivalent to the following. Names remain open for implementation design.

### Thin billing-party identity

A single `BookingBillingParty`-style record identifies who may own folio windows or receive routed charges for one booking. It is a thin identity layer, not a billing-configuration or settlement table.

It uses an explicit party kind and concrete nullable foreign keys, protected by a database constraint requiring exactly one identity. The first release must represent:

- a `BookingGuest` from the same booking;
- a hotel corporate/government account.

Future extensions may add:

- a hotel agency account after an agency account domain exists; and
- a booking-only contact snapshot after operational demand justifies it.

This is not a generic Rails polymorphic association. Concrete foreign keys preserve database integrity. Guest parties reference `BookingGuest`, preserving the rule that a guest can be billed only within a booking to which that guest is attached. A uniqueness constraint on booking and `booking_guest_id` prevents duplicate guest billing parties.

Folios should reference that billing identity explicitly. Multiple folios may reference the same party.

The billing-party record must not absorb settlement terms, routing coverage, tax inclusion behavior, or ledger state. Those concerns remain separate:

```text
Billing Party
Who may be billed or own folios

Billing Terms
How that party expects to settle: PO, voucher, direct bill reference, payment preference

Folio Window
The concrete ledger owned by a billing party

Routing Rule
Which concrete folio receives a transaction code

Tax Inclusion Override
Booking-local include/exclude behavior for attached taxes and charges
```

If PO numbers, vouchers, authorization references, settlement preferences, or direct-bill terms need to be editable per booking party, they should live in a separate billing-terms concept rather than on the billing-party identity itself.

### Booking tax-inclusion override

A booking-local record must be able to express:

- booking;
- parent transaction code;
- primary tax key or hotel tax;
- include or exclude behavior;
- actor, reason, and timestamps; and
- optionally group-derived provenance if bulk group application is added.

The record should not duplicate or rewrite the hotel default. It should resolve against it.

### Effective routing projection

The UI needs one effective row per eligible parent transaction code, regardless of whether the target comes from:

- primary-folio fallback;
- a group-derived rule;
- a booking-local rule; or
- a protected system policy.

Historical inactive rules belong in Audit Trails, not in the operational projection.

### Controlled routing mutation

The routing command should:

1. validate booking, hotel, folio, currency, permissions, and financial-date rules;
2. calculate affected posted charges and upcoming items;
3. return a preview before mutation when existing charges are eligible;
4. persist the routing change;
5. optionally move existing charges using auditable transfer/split operations;
6. update permitted upcoming forecasts;
7. record actor, reason, source, destination, and lineage; and
8. avoid partially applied results if a movement fails.

## Required invariants

- Every folio belongs to one concrete booking.
- A group view never becomes a consolidated ledger.
- A billing party may own multiple folios in one booking.
- Creating a folio does not change routing automatically.
- Every effective route points to an open folio from the same booking and hotel.
- A transaction-code row appears once in the main operational table.
- Inclusion-generated tax/charge codes appear beneath their parent, not as duplicate parents.
- Attached items follow the parent unless an explicit child routing exception exists.
- A booking-local inclusion change never mutates hotel defaults.
- A child-booking change never mutates group configuration.
- A hotel-default change requires hotel-level permission and impact confirmation.
- Posted transactions are not rewritten in place.
- Existing-charge movement is explicit, previewed, and auditable.
- Tourism-tax responsibility remains guest-directed unless an authorized explicit policy changes its target.
- Closed or voided folios cannot become routing targets.
- Removing a guest or billing party cannot orphan folios, transactions, invoices, deposits, or routing lineage.
- Repeated saves and retries must not duplicate folios, routing movements, or inclusion overrides.

## Recommended delivery order

This work crosses the concerns identified by Phases 3, 4, and 6. A safe implementation order is:

```text
1. Thin billing-party identity and automatic BookingGuest projection
2. Billing Preferences party-list presentation
3. Flexible folio creation from billing parties
4. Effective one-row-per-code Billing Instructions projection
5. Inline routing edit and atomic impact confirmation
6. Collapsible tax-inclusion presentation
7. Booking-local tax include/exclude overrides
8. Hotel-scope inclusion warning and impact preview
9. Folio Operations center simplification
10. Group-scope presentation and explicit bulk actions
11. Reconciliation, permissions, audit, and system coverage
```

This order establishes identity and folio ownership before routing and tax behavior depend on them.

## Validation scenarios

At minimum, the resulting feature should verify:

- adding a guest immediately makes that guest selectable as a folio sharer;
- primary-guest changes do not rewrite existing folio ownership;
- one guest can own two or more folios;
- creating a second folio does not alter existing routes;
- every active routable system and custom parent code appears exactly once;
- non-routable payment and system-control codes are excluded by the shared eligibility rule;
- tax-generated codes do not appear as top-level rows;
- every parent row expands, including an empty-inclusion row;
- hotel defaults, booking additions, and booking exclusions resolve correctly;
- removing a hotel-default inclusion for one booking does not change another booking;
- global inclusion changes require hotel-level permission and confirmation;
- parent routing changes preserve explicit child exceptions;
- route previews count and total only eligible posted charges;
- future-only changes leave posted transactions untouched;
- existing-and-future changes retain transfer/split lineage;
- a failed movement does not leave a partially applied routing operation;
- closed folios cannot be selected as targets;
- a guest cannot become a billing party for a sibling booking without first being attached to that sibling as a `BookingGuest`;
- group child changes do not alter unselected siblings or group defaults;
- Folio Operations retains its left rail and has no Forecast or Activity tabs;
- Folio Operations provides forecasts in a collapsed Upcoming section separate from posted transactions; and
- Audit Trails retains the historical record removed from operational tables.

## Resolved product questions

1. Billing parties use one thin identity record with explicit typed foreign keys and an exactly-one-identity database constraint, not a generic polymorphic association.
2. Billing-party identity must not contain settlement terms, routing coverage, tax inclusion behavior, or ledger state. Those remain separate concepts.
3. `Other billing contact` is deferred. The first release supports guests and company/government accounts.
4. Agency billing is deferred until a hotel-scoped agency account model exists.
5. Guest billing responsibility is booking-local. A guest is automatically available only to bookings where that person has a `BookingGuest`; companies may be applied explicitly across selected child bookings.
6. Non-routable payment and system-control codes are excluded from Billing Instructions. All routable system and custom parent codes remain visible.
7. Forecasts appear in a collapsed expandable Upcoming section in Folio Operations, with no Forecast tab and no mixing with posted transactions.
