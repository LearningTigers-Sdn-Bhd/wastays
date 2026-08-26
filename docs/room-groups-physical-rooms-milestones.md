# Room Groups and Physical Rooms Milestones

Status: Approved
Implementation status: Milestones 0–2 complete
Date: 2026-08-26

## Purpose

This proposal separates physical-room management from room-group assignment.

Room Inventory manages room types, room-number generation, room quantities, and rate plans. Room Groups assigns existing physical rooms to optional groups.

The recommended production release point is Milestone 5. Milestone 6 provides long-term identity hardening.

## Agreed responsibilities

### Room Inventory

Room Inventory manages:

- Room types.
- Room-number generation.
- Manual room-number entry.
- Room quantities.
- Rate plans.
- Capacity, amenities, and restrictions.

Room Inventory assigns each physical room to one room type. It does not assign a room group.

### Room Groups

Room Groups manages:

- Group names.
- Room selection.
- Group assignment.
- Removal of rooms from a group.

A room group can contain rooms from multiple room types. Room Groups does not create, rename, or remove room numbers.

### Operational views

Housekeeping and Stay View support these display modes:

- Flat.
- Grouped by room type.
- Grouped by room group.

Rooms without a room group appear in an **Ungrouped** section.

## Milestone 0 — Confirm the domain rules

This milestone defines the product rules before the database migration.

Approved rules:

- A room number is unique within one hotel.
- Room numbers are normalized by trimming whitespace. Comparison remains case-sensitive.
- A duplicate preflight blocks migration. It never merges rooms automatically.
- A room belongs to one room type.
- A room belongs to zero or one room group.
- Staff archive a room instead of deleting it.
- A room type owns each room through Milestone 2.
- A room type group remains authoritative through Milestone 2.
- Backfilled and new rooms inherit the room type group through Milestone 2.
- The room type quantity remains authoritative through Milestone 2.
- A numbered room type has one active physical room for each quantity unit.
- Quantity-only inventory remains available for hotels without room numbers.
- Room numbers and room types are immutable after room creation.
- Room-number list changes do not infer a rename.
- A removed number archives its room.
- An added number creates or restores a room.
- Archived room numbers remain reserved within the hotel.
- Room renaming and room-type transfer remain out of scope.
- Existing room-type deletion behavior remains unchanged.

### Exit criteria

- The product rules have approval.
- The migration behavior has approval.
- Empty, duplicate, rename, archive, and restore cases have defined results.

Run `bin/rails rooms:audit_legacy_directory` before the schema migration. The command is read-only and exits unsuccessfully when blank, untrimmed, duplicate, or quantity-mismatch data must be corrected.

## Milestone 1 — Add the physical-room foundation

This milestone adds physical rooms without changing existing application behavior.

Proposed table:

```text
rooms
- id
- hotel_id
- room_type_id
- room_group_id
- number
- position
- archived_at
- created_at
- updated_at
```

Required database controls:

- A unique index on `hotel_id` and `number`, including archived rooms.
- An index on `room_type_id`.
- An index on `room_group_id`.
- Foreign keys for the hotel, room type, and optional room group.

Scope:

- Add the `Room` model and its associations.
- Backfill rooms from `room_types.room_numbers`.
- Copy each room type group to its physical rooms.
- Preserve room-number order with a `position` value.
- Add a reconciliation service.
- Keep the JSON field as the active source.

The reconciliation service compares:

- JSON room numbers.
- Physical-room records.
- Room-type ownership.
- Room-group assignment.
- Duplicate and missing records.

### Exit criteria

- Every JSON room number has one physical-room record.
- Every physical room belongs to the correct hotel and room type.
- Existing room-group assignment transfers correctly.
- Existing booking, housekeeping, and availability behavior remains unchanged.
- The migration can operate more than once without creating duplicates.

## Milestone 2 — Connect Room Inventory to physical rooms

This milestone keeps the current room-number generator in Room Inventory.

Scope:

- Preserve the range and manual-entry controls.
- Save physical-room records through a service.
- Continue to write the JSON field.
- Create room records for new numbers.
- Preserve room records for unchanged numbers.
- Archive removed room records.
- Treat removed and added numbers as separate records.
- Keep the save operation transactional.

The save service protects:

- Bookings outside cancelled, completed, or voided states.
- Incomplete current or future room blocks.
- Active room locks.
- Open housekeeping tasks, including tasks linked through a booking room.

Room statuses, completed bookings, completed blocks, and audit records do not block archival. A restored room keeps its previous room-group assignment. A new room inherits the room type group through Milestone 2.

### Exit criteria

- Creating a room type creates the expected rooms.
- Editing the number list updates rooms and JSON together.
- Removing a number archives the room.
- Reordering room numbers does not recreate rooms.
- A failed update changes neither source.
- Onboarding and normal settings produce the same records.

## Milestone 3 — Change Room Groups to room assignment

This milestone changes Room Groups from room-type grouping to physical-room grouping.

Example:

```text
Group name: Main Wing

Rooms:
☑ 101 — Deluxe King
☑ 102 — Deluxe King
☐ 103 — Deluxe Twin
☑ 201 — Family Suite
```

Scope:

- List existing rooms from all room types.
- Add search by room number and room-type name.
- Add a room-type filter.
- Assign selected rooms to one group.
- Move a room from its previous group when necessary.
- Show unassigned rooms.
- Show the number of assigned physical rooms.
- Remove room-group assignment from the room-type form.
- Stop the existing room-type assignment service.

### Exit criteria

- One group can contain rooms from multiple room types.
- One room cannot belong to two groups.
- Removing a room from a group does not remove the room.
- Deleting a group makes its rooms unassigned.
- Room Inventory cannot assign a group.
- Existing group data remains available after conversion.

## Milestone 4 — Add operational grouping

This milestone uses physical rooms in Housekeeping and Stay View.

### Housekeeping scope

- Add the flat display mode.
- Add grouping by room type.
- Add grouping by room group.
- Add a room-group filter.
- Add an **Ungrouped** section.
- Apply the same grouping to PDF, Excel, and CSV exports.

Housekeeping continues to update room statuses with the current room identity during this milestone.

### Stay View scope

- Add the flat display mode.
- Add grouping by room type.
- Add grouping by room group.
- Add a room-group filter.
- Add an **Ungrouped** section.

Room cards, booking bars, rates, and operational actions remain unchanged.

### Exit criteria

- Both views contain the same physical-room count.
- Flat and grouped views contain the same rooms.
- Each room appears once.
- Grouping does not change a booking or room status.
- Unassigned rooms remain visible.
- Existing room-type filters continue to work.
- Exports match the Housekeeping screen.

## Milestone 5 — Make physical rooms authoritative

This milestone changes room enumeration from JSON to the `rooms` table.

Scope:

- Read room numbers from active physical-room records.
- Update availability to use physical rooms.
- Update Housekeeping to load physical rooms.
- Update Stay View to load physical rooms.
- Update room-number selection in bookings.
- Update room locks and room-status lookup.
- Update room blocks and inventory synchronization.
- Keep the JSON field as a temporary compatibility copy.
- Reconcile both sources after each important write.

During this milestone:

```text
rooms table = source of truth
JSON field  = compatibility copy
```

### Exit criteria

- Application reads no longer depend on the JSON room list.
- Reconciliation reports no differences.
- Booking assignment finds the same available rooms.
- Room statuses and blocks resolve to the correct room.
- Housekeeping and Stay View show the expected rooms.
- Focused domain suites pass.
- Full CI passes.
- The release migration has a tested rollback procedure.

This milestone is the recommended production release point.

## Milestone 6 — Harden identity and remove legacy fields

This milestone removes the remaining dependence on room numbers as identifiers.

Add nullable `room_id` references to relevant records:

- `booking_rooms`.
- `room_statuses`.
- `room_blocks`.
- `room_locks`.
- `room_operational_audit_logs`.
- Relevant housekeeping records.

Keep historical snapshots:

```text
room_id       # Stable physical-room identity
room_type_id  # Booked or historical room category
room_number   # Historical display value
```

Scope:

- Backfill each `room_id`.
- Add dual-write behavior.
- Change operational lookups to `room_id`.
- Add foreign keys and indexes.
- Remove the JSON room-number field.
- Remove `room_types.room_group_id`.
- Remove obsolete assignment routes and services.
- Remove temporary reconciliation code after a stable period.

### Exit criteria

- Renaming a room does not disconnect its history.
- Room status, blocks, locks, and bookings use stable room identity.
- Historical documents retain their original room number and room type.
- No application code reads the old JSON field.
- No application code reads `room_types.room_group_id`.
- Full CI and migration tests pass.

## Delivery boundaries

| Milestones | Outcome |
| --- | --- |
| 0–2 | Physical-room foundation and safe room-number generation |
| 3 | Room Groups assigns selected physical rooms |
| 4 | Housekeeping and Stay View support room grouping |
| 5 | Physical rooms become the production source of truth |
| 6 | Stable room identity and legacy cleanup |

Use one scoped branch and review for each milestone. Milestones 1 and 2 remain additive and reversible.

Milestone 5 is the main release gate. Milestone 6 can follow as a separate hardening project.
