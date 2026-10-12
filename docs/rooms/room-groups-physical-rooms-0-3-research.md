# Physical Rooms: Research and Planning for Milestones 0 to 3

Status: Record of work
Branch: `refactor/room-grouping`
Date: 2026-08-27

## Purpose

This document records the research, stabilization work, and planning decisions for Milestones 0 to 3. The full plan is in [the milestones document](room-groups-physical-rooms-milestones.md).

## 1. The research question

Room numbers live in one JSON column, `room_types.room_numbers`. A room has no record of its own. As a result, a room cannot carry a group, a status history, or a stable identity.

The plan adds a `rooms` table. The research had to answer one question first: can an ordinary migration read the JSON and create one room for each number?

The answer depends on the legacy data. A room number must be unique inside one hotel. The JSON column gives no such guarantee.

## 2. What the audit found

The branch provides the supported read-only command `bin/rails rooms:audit_legacy_directory`. It reports blank, untrimmed, duplicate, and quantity-mismatch data. It changes no records.

```text
production   1 test hotel affected
demo         many hotels affected
local        2 of 5 numbered hotels affected (id 8, id 20)
```

Every invalid numbered-room finding blocks the migration. This rule includes blank values, outer spaces, all duplicates, and quantity mismatches. An empty list remains valid for quantity-only inventory.

Demo and local data are disposable. Production needs one test hotel corrected. As a result, the plan dropped the earlier readiness column and the admin backfill screen. Those parts solved a problem that the data does not have.

## 3. The defect behind the duplicates

The duplicates come from the application, not from old data. The room-number generator starts at 101 for each room type. It does not read the numbers that other room types in the same hotel already use.

```text
staff add room type A ──▶ generator starts at 101 ──▶ 101, 102, 103
staff add room type B ──▶ generator starts at 101 ──▶ 101, 102, 103  ← duplicate
```

Every seeder produces floor-based numbers. No seeder can make a duplicate. As a result, each duplicate came from a person who used Room Inventory.

This finding changed the plan. A data fix alone is not enough. The generator needs a correction in the same release, or clean data becomes dirty again.

## 4. Milestone 0 — rules and audit

Milestone 0 is complete. It changed no records.

The branch locked 18 product rules in the milestones document. The rules that drive the schema are these:

- A room number is unique within one hotel.
- Numbers are trimmed. Comparison stays case-sensitive.
- A room belongs to one room type and to zero or one room group.
- Staff archive a room instead of deleting it.
- Archived numbers stay reserved within the hotel.
- The room type stays authoritative through Milestone 3.

The research also named four meanings of a duplicate number: incorrect legacy data, stale demo data, one physical room sold under two room types, and a display number that is unique only inside its room type. The last two cases make the hotel-wide rule wrong for that hotel. Classify a finding before you correct it.

## 5. Milestone 1 — data correction

Milestone 1 is open. It ships no code.

The work is operational: correct every production finding, reseed demo, and reseed or correct local data. Run the supported audit after each correction.

CAUTION: Run the audit again immediately before the deploy. A person can add a new duplicate in the days between the data fix and the release.

## 6. Milestone 2 — schema, backfill, and the generator

The branch contains the schema, strict backfill, supported audit, numbering context, and generator correction. Validation remains part of the stabilization checkpoint.

### What shipped

`db/migrate/20260826130000_create_rooms.rb` creates the table with these controls:

- A unique index on `hotel_id` and `number`, archived rooms included.
- Indexes on `hotel_id, archived_at` and on `room_type_id, archived_at, position`.
- Foreign keys for the hotel, the room type, and the optional room group.
- A check constraint `rooms_number_normalized` that rejects untrimmed and empty numbers.

`db/migrate/20260826131000_backfill_rooms_from_room_types.rb` reads the JSON and creates one room for each valid number. It uses `find_or_initialize_by` on hotel and number, so a repeated run creates no duplicate. It reports every blocking finding before it writes a room.

`app/models/room.rb` normalizes the number before validation and enforces hotel-wide uniqueness. It rejects direct changes to the number and room type. `archive!` and `restore!` replace deletion.

`app/services/rooms/audit_legacy_directory.rb` holds the audit as a service. Milestone 6 reuses it for reconciliation. `app/services/rooms/reconcile_directory.rb` compares both sources.

`Rooms::NumberingContext` supplies the numbers reserved by other room types and the next numeric start. The Room Inventory form passes this data to the Stimulus controller. The controller warns about conflicts before save. The transactional save service remains authoritative.

The supported audit task stays in the branch. Operations run it against the release artifact immediately before migration.

## 7. Milestone 3 — one save writes both sources

The branch shipped Milestone 3.

`HotelPortal::RoomTypes::SaveRoomType` now wraps the save in a transaction. It locks the room type, saves the JSON field, then calls `Rooms::SyncFromRoomType`. A failure in either step rolls back both.

```text
save ──▶ lock room type ──▶ write room_numbers JSON ──▶ sync rooms ──▶ commit
                                                  └── failure ──▶ rollback both
```

`Rooms::SyncFromRoomType` does this work:

- Trims each number and rejects blank entries.
- Rejects a repeated number inside one list.
- Locks the rooms of the hotel and rejects a number that another room type owns.
- Archives a removed number and restores an added number that exists.
- Writes `position` from the order of the list, so reordering creates no room.

`Rooms::RemovalGuard` blocks the archival of a room that has an active booking, a current or future room block, an active room lock, or an open housekeeping task. Room statuses, completed bookings, completed blocks, and audit records do not block archival.

Specs cover the model, both migrations, numbering context, portal saves, onboarding, seed writes, synchronization, removal guards, reconciliation, and the audit task.

## 8. Remaining gates

The focused Milestones 0 to 3 suite passed with 100 examples and no failures. Canonical `bin/ci` passed 7,875 examples and every isolated migration spec. RuboCop, Brakeman, dependency audits, Import Map checks, and the Tailwind build also passed.

The local audit passed after floor-based renumbering of hotels 8 and 20. The local backfill migration then completed successfully. Reconciliation passed for every local hotel.

The remaining gates are:

1. Correct every Milestone 1 finding in production and demo data.
2. Require a clean audit and reconciliation result before Milestone 4.
3. Continue the same pull request through Milestone 6 before production release.
