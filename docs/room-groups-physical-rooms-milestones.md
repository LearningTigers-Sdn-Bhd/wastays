# Room Groups and Physical Rooms Milestones

Status: Approved
Implementation status: Milestones 0 and 1 complete on local, demo, and production. Milestones 2 to 7 complete on the branch.
Date: 2026-08-26

## Purpose

This proposal separates physical-room management from room-group assignment.

Room Inventory manages room types, room-number generation, room quantities, and rate plans. Room Groups assigns existing physical rooms to optional groups.

Milestones 0 to 6 ship as one branch and one pull request. Milestone 7 follows as a separate project.

## Why this plan changed

An earlier version put the backfill inside a Rails migration and raised for the whole database on any duplicate. That version made clean legacy data a condition of deployment.

A later version added per-hotel readiness tracking, a readiness column, and an admin backfill screen. That version solved a problem that the data does not have.

The audit settled it:

```text
production   1 test hotel affected
demo         many hotels affected
local        2 of 5 numbered hotels affected (id 8, id 20)
```

Demo and local data are disposable. Production needs one hotel corrected. As a result, this plan uses an ordinary backfill migration and no readiness machinery.

### The real defect

The source of every duplicate is the application, not old data. The room-number generator starts at 101 for each room type. It does not read the numbers that other room types in the same hotel already use.

```text
staff add room type A ──▶ generator starts at 101 ──▶ 101, 102, 103
staff add room type B ──▶ generator starts at 101 ──▶ 101, 102, 103  ← duplicate
```

Every seeder produces correct floor-based numbers. No seeder can make a duplicate. As a result, each duplicate in demo and production came from a person who used Room Inventory.

Milestone 2 corrects the generator. Without that correction, clean data becomes dirty again and the next migration hits the same wall.

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

## Milestone 0 — Confirm the rules and audit the data

This milestone defines the product rules and measures the legacy data. It changes no records.

### Approved rules

- A room number is unique within one hotel.
- Room numbers are normalized by trimming whitespace. Comparison remains case-sensitive.
- Room Inventory must generate room numbers that are unique within the hotel.
- Nothing merges or renames a room automatically.
- A room belongs to one room type.
- A room belongs to zero or one room group.
- Staff archive a room instead of deleting it.
- A room type owns each room through Milestone 3.
- A room type group remains authoritative through Milestone 3.
- Backfilled and new rooms inherit the room type group through Milestone 3.
- The room type quantity remains authoritative through Milestone 3.
- A numbered room type has one active physical room for each quantity unit.
- Quantity-only inventory remains available for hotels without room numbers.
- Room numbers and room types are immutable after room creation.
- Room-number list changes do not infer a rename.
- A removed number archives its room.
- An added number creates or restores a room.
- Archived room numbers remain reserved within the hotel.
- Room renaming and room-type transfer remain out of scope.
- Existing room-type deletion behavior remains unchanged.

### The audit

Run `bin/rails rooms:audit_legacy_directory` against production, demo, and local data. The supported task is read-only. It names each affected hotel and changes no records. Milestone 7 removed this task.

Each of these findings blocks the backfill:

- A blank room number.
- An untrimmed room number.
- A duplicate inside one room type.
- A duplicate across room types in one hotel.
- A difference between the quantity and the number-list size.

An empty number list remains valid for quantity-only inventory.

### Classify each finding before you change data

A duplicate room number can mean four different things:

- Incorrect legacy data.
- Stale demo data.
- One physical room sold under two room types.
- A display number that is unique only inside its room type.

The last two cases can make the hotel-wide rule wrong for that hotel. Classify each one before you correct it.

### Exit criteria

- The product rules have approval.
- The audit ran against production and demo.
- Each finding has a classification.
- No production record changed.

## Milestone 1 — Prepare the data

This milestone corrects the duplicates so that an ordinary migration can run. It ships no code.

Done. Operations ran Rails console scripts on each environment.

### Production

Complete. One test hotel was affected. It moved to the new floor-based numbering.

### Demo

Complete. The affected hotels moved to the new floor-based numbering.

### Local

Complete. Hotel 8 and hotel 20 use the new numbering.

### Exit criteria

- The audit reports zero blocking findings on production.
- The audit reports zero blocking findings on demo.
- No booking, room block, or housekeeping task points at a renamed room.

## Milestone 2 — Add the schema, backfill, and correct the generator

This milestone adds physical rooms and stops the application from making new duplicates.

### Table

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
- A check constraint that rejects untrimmed and empty numbers.

### The backfill migration

An ordinary data migration reads `room_types.room_numbers` and creates one room for each number. It is idempotent, so a repeated run creates no duplicate.

The migration applies the same blocking rules as the audit. It reports all findings before it writes a room. A migration must fail loudly instead of writing wrong data.

CAUTION: Run the audit again immediately before you deploy. Milestone 1 can go stale if a person adds a duplicate in the days between the data fix and the release.

### Keep the supported audit task

Keep `lib/tasks/rooms.rake`, its spec, and `Rooms::AuditLegacyDirectory`. Operations must run the task immediately before migration. Milestone 7 removed all three, because the legacy source they read is gone.

### The generator

Correct `room_number_generator_controller.js`:

- Pass the numbers that the hotel already uses into the generator.
- Start the default range above the highest used number.
- Show an inline warning when a typed number already belongs to another room type.
- Keep the save service as the authoritative conflict control.

### Exit criteria

- The migration creates one room for each JSON room number.
- Every room belongs to the correct hotel and room type.
- Existing room-group assignment transfers correctly.
- Running the migration twice creates no duplicate.
- Booking, housekeeping, and availability behavior is unchanged.
- The generator proposes no number that the hotel already uses.

## Milestone 3 — Connect Room Inventory to physical rooms

This milestone writes both sources from one save.

Room Inventory keeps the range control and the manual-entry control. The save service:

- Writes the JSON field and the rooms in one transaction.
- Creates room records for new numbers.
- Preserves room records for unchanged numbers.
- Archives removed room records.
- Treats a removed number and an added number as separate records.
- Rejects a number that already belongs to another room type, with a clear message.

The save service protects:

- Bookings outside cancelled, completed, or voided states.
- Incomplete current or future room blocks.
- Active room locks.
- Open housekeeping tasks, including tasks linked through a booking room.

Room statuses, completed bookings, completed blocks, and audit records do not block archival. A restored room keeps its previous room-group assignment. A new room inherits the room type group through Milestone 3.

Onboarding calls the same save service. As a result, onboarding and normal settings produce the same records.

### Exit criteria

- Creating a room type creates the expected rooms.
- Editing the number list updates rooms and JSON together.
- Removing a number archives the room.
- Reordering room numbers does not recreate rooms.
- A failed update changes neither source.
- Onboarding and normal settings produce the same records.
- A duplicate number gives a clear error instead of a silent write.

## Milestone 4 — Change Room Groups to room assignment

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

- List unassigned rooms from all room types.
- When staff edit a group, also list the rooms in that group.
- Hide rooms that belong to another group.
- Add search by room number and room-type name.
- Add a room-type filter.
- Assign selected rooms to one group.
- To move a room, first remove it from its current group. Then assign it to the new group.
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

## Milestone 5 — Add operational grouping

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
- Each room appears one time.
- Grouping does not change a booking or a room status.
- Unassigned rooms remain visible.
- Existing room-type filters continue to work.
- Exports match the Housekeeping screen.

## Milestone 6 — Make physical rooms authoritative

This milestone changes room enumeration from JSON to the `rooms` table.

Done on the branch.

WARNING: This milestone changes the read source for availability, bookings, Housekeeping, and Stay View. It carries the largest operational risk in this project. Do not start it until every earlier milestone passes.

`Rooms::DirectoryQuery` holds the single answer to "which rooms exist". It reads active rooms in `position` order, for one hotel or for one room category. Every operational read calls it. `Rooms::GroupAssignmentsQuery` reads the same loaded rows, so a board asks the `rooms` table once.

Milestone 7 removed the reconciliation task and the audit task. There is one source now, so there is nothing left to compare.

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
- Reconciliation reports no difference.
- Booking assignment finds the same available rooms.
- Room statuses and blocks resolve to the correct room.
- Housekeeping and Stay View show the expected rooms.
- Focused domain suites pass.
- `bin/ci` passes.
- The release has a tested rollback procedure.

## Milestone 7 — Harden identity and remove legacy fields

Done on the branch.

`RoomIdentifiable` keeps `room_id` in step on every write. `RoomType#room_numbers` is no longer a column: it reads the physical rooms, and it accepts a list that `Rooms::SyncFromRoomType` writes.

Nullable `room_id` references on:

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
- Change operational lookups to `room_id`. Not done, and not planned. It would re-key every operational table and its indexes. `room_id` plus `Rooms::Rename` already deliver what it was for, so the lookups stay on hotel, room type, and number.
- Add foreign keys and indexes.
- Remove the JSON room-number field.
- Remove `room_types.room_group_id`.
- Remove obsolete assignment routes and services.
- Remove temporary reconciliation code after a stable period.

### How a rename keeps its history

`Rooms::Rename` changes the number and keeps the room id. Two groups of records answer two different questions, so they behave differently:

```text
room_statuses, room_blocks, room_locks ──▶ take the new number
booking_rooms, audit logs              ──▶ keep the number they were written with
```

A room status describes the room as it is today, so it must show today's number. A folio, a registration card, or an audit trail states what happened at the time, and a later rename must not change that.

The boards read the number from the `rooms` table, so they show the new number at once.

The service has no screen yet. Room Inventory still edits the room list, where removing a number archives a room and adding one creates a room.

### Exit criteria

- Renaming a room does not disconnect its history.
- Room status, blocks, locks, and bookings use stable room identity through `room_id`.
- Historical documents retain their original room number and room type.
- No application code reads the old JSON field.
- No application code reads `room_types.room_group_id`.
- Full CI and migration tests pass.

## Correcting a blocked hotel

Renumber by floor. Hotel 8 in the local database is the example. Five room types each start at 101.

```text
rt 16 Ocean Villa King      qty=10  ──▶ 101–110
rt 17 Executive Penthouse   qty=3   ──▶ 201–203
rt 18 Garden Prestige Suite qty=8   ──▶ 301–308
rt 19 Skyline Queen Deluxe  qty=14  ──▶ 401–414
rt 23 Spa Villa             qty=3   ──▶ 501–503
```

Procedure:

1. Run the audit and read the findings for the hotel.
2. Classify each duplicate against the four cases in Milestone 0.
3. Renumber the room types in Room Inventory.
4. Run the audit again for the hotel.

CAUTION: Do not renumber a production hotel before you classify its findings. A wrong correction points a live booking at the wrong room.

Demo and local data are safe to reseed at any time.

## Delivery boundaries

| Milestone | Outcome |
| --- | --- |
| 0 | Rules approved and legacy data measured |
| 1 | Duplicates corrected on production, demo, and local |
| 2 | Rooms table, backfill, and a generator that makes unique numbers |
| 3 | Room Inventory writes JSON and rooms together |
| 4 | Room Groups assigns selected physical rooms |
| 5 | Housekeeping and Stay View support room grouping |
| 6 | Physical rooms become the source of truth |
| 7 | Stable room identity and legacy cleanup |

Milestones 0 to 7 ship as one branch and one pull request.

Milestones 2, 3, and 7's references are additive and reversible. Milestone 6 is the release gate. The column removal in Milestone 7 rebuilds `room_numbers` from the physical rooms when it rolls back.
