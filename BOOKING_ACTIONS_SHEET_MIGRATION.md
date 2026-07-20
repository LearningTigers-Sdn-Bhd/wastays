# Booking Actions Sheet Migration

## Purpose

Create a new Sheet-based implementation for booking actions under
`HotelPortal::Bookings::Actions`. The existing Offcanvas implementation remains
isolated while callers are migrated and will be retired after it has no booking
consumers.

The new implementation must not use Offcanvas names, frame identifiers,
completion actions, controllers, or compatibility behavior.

## Architecture boundary

```text
HotelPortal::Bookings::Actions
├── Owns Sheet-based booking workflows
├── Uses existing booking services and policies
├── Owns its frame and completion contract
└── Does not depend on the Offcanvas implementation
```

The server-side booking-action contract should contain only:

```text
Booking action response
├── booking_action_sheet target
├── complete PanelsUI::Sheet response
├── optional destination URL on completion
└── flash or validation feedback
```

## Complete booking-action surface

| Group | Actions requiring the new Sheet implementation |
|---|---|
| Booking creation | Quick booking, full new booking, walk-in check-in, backdated check-in without an existing booking |
| Booking overview | Show booking summary, group Print/Send, audit trail |
| Stay editing | Edit booking, amend stay, change room/timeline, move or reassign, change dates |
| Check-in lifecycle | Check in, edit check-in time, backdated check-in for an existing booking, undo check-in |
| Checkout lifecycle | Review late checkout, complete checkout, checkout-required resolution, early-departure checkout |
| Exception lifecycle | Cancel booking, mark no-show, reinstate no-show, repair no-show folio |
| Guest management | Add guest, edit primary guest, edit additional guest, remove guest, make primary guest |
| Internal notes | Add note, edit note, view note history, delete note |
| Registration notes | List templates, create template, edit template |
| Supporting read-only | Audit history, document, receipt, invoice, and registration-card links |

## Status-driven lifecycle actions

| Booking status | Available Sheet actions |
|---|---|
| `pending` / `overbooked` | Cancel |
| `confirmed` | Check in, Cancel |
| `review_no_show` | Backdated check-in, Mark no-show, Cancel |
| `checked_in` | Check out, Edit check-in time, Undo check-in |
| `review_due_out` | Review late checkout |
| `checkout_required` | Complete checkout |
| `no_show` | Reinstate and, when applicable, Repair no-show folio |
| Group booking | The applicable lifecycle actions with group target selection |

## Naming contract

| Purpose | Name |
|---|---|
| Turbo Frame | `booking_action_sheet` |
| Controller namespace | `HotelPortal::Bookings::Actions` |
| Shared controller | `HotelPortal::Bookings::Actions::BaseController` |
| Completion operation | `complete_booking_action` |
| Application Stimulus namespace | `booking-actions--sheet` |
| View root | `hotel_portal/bookings/actions` |

No new file or API in this implementation should use `offcanvas`, `drawer`, or
generic `overlay` terminology.

## Proposed controller structure

```text
app/controllers/hotel_portal/bookings/actions/
├── base_controller.rb
│
├── new_bookings_controller.rb
├── walk_in_check_ins_controller.rb
├── backdated_check_ins_controller.rb
│
├── summaries_controller.rb
├── documents_controller.rb
├── audit_trails_controller.rb
│
├── booking_edits_controller.rb
├── stay_amendments_controller.rb
├── room_assignments_controller.rb
├── booking_moves_controller.rb
├── booking_dates_controller.rb
│
├── check_ins_controller.rb
├── undo_check_ins_controller.rb
├── late_checkouts_controller.rb
├── checkouts_controller.rb
│
├── cancellations_controller.rb
├── no_shows_controller.rb
├── reinstatements_controller.rb
├── no_show_folio_repairs_controller.rb
│
├── guests_controller.rb
├── guest_confirmations_controller.rb
├── internal_notes_controller.rb
├── note_confirmations_controller.rb
└── registration_note_templates_controller.rb
```

## Proposed view structure

```text
app/views/hotel_portal/bookings/actions/
├── shared/
│   ├── _sheet.html.erb
│   ├── _errors.html.erb
│   └── _group_target_selector.html.erb
│
├── new_bookings/
│   ├── new.html.erb
│   └── _form.html.erb
│
├── walk_in_check_ins/
│   ├── new.html.erb
│   └── _form.html.erb
│
├── backdated_check_ins/
│   ├── new.html.erb
│   └── _form.html.erb
│
├── summaries/
│   └── show.html.erb
│
├── documents/
│   └── show.html.erb
│
├── audit_trails/
│   └── show.html.erb
│
├── booking_edits/
│   ├── edit.html.erb
│   └── _form.html.erb
│
├── stay_amendments/
│   ├── edit.html.erb
│   └── _form.html.erb
│
├── room_assignments/
│   ├── edit.html.erb
│   └── _form.html.erb
│
├── booking_moves/
│   ├── edit.html.erb
│   └── _form.html.erb
│
├── booking_dates/
│   ├── edit.html.erb
│   └── _form.html.erb
│
├── check_ins/
│   ├── new.html.erb
│   └── _form.html.erb
│
├── undo_check_ins/
│   ├── new.html.erb
│   └── _form.html.erb
│
├── late_checkouts/
│   ├── new.html.erb
│   └── _form.html.erb
│
├── checkouts/
│   ├── new.html.erb
│   ├── _form.html.erb
│   ├── _folio_list.html.erb
│   ├── _early_departure.html.erb
│   └── _settlement_details.html.erb
│
├── cancellations/
│   ├── new.html.erb
│   └── _form.html.erb
│
├── no_shows/
│   ├── new.html.erb
│   └── _form.html.erb
│
├── reinstatements/
│   ├── new.html.erb
│   └── _form.html.erb
│
├── no_show_folio_repairs/
│   ├── new.html.erb
│   └── _confirmation.html.erb
│
├── guests/
│   ├── new.html.erb
│   ├── edit.html.erb
│   └── _form.html.erb
│
├── internal_notes/
│   ├── new.html.erb
│   ├── edit.html.erb
│   ├── history.html.erb
│   └── _form.html.erb
│
├── confirmations/
│   └── show.html.erb
│
└── registration_note_templates/
    ├── index.html.erb
    ├── new.html.erb
    ├── edit.html.erb
    └── _form.html.erb
```

## Shared behavior

The initial implementation should place shared behavior in
`Actions::BaseController`, not in a new concern.

```text
Actions::BaseController
├── Authorize booking management
├── Load the booking through current_hotel
├── Validate the return destination
├── Provide Turbo and HTML response handling
└── Produce complete_booking_action responses
```

A separate concern is justified only if another controller hierarchy later
needs the same behavior.

Business logic must remain in the existing domain services. Controllers in the
new namespace orchestrate authorization, input, rendering, and responses; they
must not copy business rules from the legacy controllers.

## Sheet lifecycle

```text
Booking-action launcher
└── targets booking_action_sheet
    └── Actions controller
        └── response renders
            ├── matching Turbo Frame
            └── complete PanelsUI::Sheet

Successful submission
└── complete_booking_action
    ├── close the Sheet
    ├── clear booking_action_sheet
    ├── update relevant page content
    └── optionally navigate
```

## Domain exclusions

The following workflows may be associated with a booking, but they should not
be moved into `bookings/actions` because another domain owns their behavior.

| Domain | Actions |
|---|---|
| Folios | Add, edit, close, and reopen folio windows; payments; charges; adjustments |
| Routing | Individual and group billing routes |
| Billing parties | Add or archive a party and update billing terms |
| Deposits | Allocate, refund, and reverse allocations |
| Security deposits | Collect and release |
| Hotel operations | Complete housekeeping requests and resolve complaints |
| Stay View operations | Room status, housekeeping assignment/status, and maintenance blocks |

These workflows should eventually receive Sheet implementations inside their
own domain namespaces.

```text
bookings/actions
├── Creation
├── Booking overview
├── Stay editing
├── Booking lifecycle
├── Booking exceptions
├── Guests
├── Internal notes
└── Registration-note templates

folios/actions
├── Folio windows
├── Transactions
├── Routing
└── Deposits

stay_view/actions
├── Room operations
├── Housekeeping
└── Room blocks
```

## Migration strategy

The new and legacy implementations must remain independent during migration.
Both may call the same existing services, but they should not call each other's
controllers, response helpers, JavaScript actions, or view wrappers.

```text
New implementation
└── hotel_portal/bookings/actions/**

Legacy implementation
├── hotel_portal/bookings/transactions/**
├── hotel_portal/bookings/show/actions/**
├── offcanvas_drawer
├── complete_offcanvas
└── OffcanvasTransactionCompletion
```

Recommended rollout:

1. Establish `Actions::BaseController`, `booking_action_sheet`, and the
   `complete_booking_action` contract.
2. Migrate Audit Trail to prove loading, sizing, closing, and focus restoration.
3. Migrate Cancellation to prove invalid-form handling and completion.
4. Migrate Show Booking and group Print/Send.
5. Migrate guest and internal-note management.
6. Migrate stay-editing workflows.
7. Migrate check-in and checkout lifecycle workflows.
8. Repoint launchers one action family at a time.
9. Delete each legacy booking action only after its caller count reaches zero.
10. Retire the legacy Offcanvas infrastructure after it has no remaining users.

## Acceptance requirements

Each migrated action must verify:

- the action opens inside `booking_action_sheet`;
- the Sheet has an accessible title and intentional initial focus;
- Escape, explicit dismissal, and completion restore focus correctly;
- invalid forms remain open and preserve submitted values;
- errors receive appropriate focus and announcement;
- group target selection is preserved where applicable;
- completion updates or navigates to the correct return destination;
- direct HTML requests retain a functional redirect fallback;
- mobile, desktop, reduced-motion, light-theme, and dark-theme behavior remain
  usable;
- the action no longer references Offcanvas code after migration.
