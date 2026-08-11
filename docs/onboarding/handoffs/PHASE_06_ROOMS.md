# Phase 6 — Rooms slice

Read `docs/onboarding/handoffs/README.md` first for the shared pattern and rules.

## Goal

Make the `rooms` onboarding section real: an owner can create at least one operationally
valid room type from inside the onboarding shell, without visiting the settings portal.

`PLAN.md` §"Phase 6: Rooms slice" is the scope authority.

## Prerequisite

`room_revenue` (Phase 5) must be complete — `section_catalog.rb:13` declares it as the
prerequisite, and `UpdateSection` will refuse the transition otherwise. If Phase 5 is
still a placeholder, stop and confirm with the user before proceeding.

## Deliverables

- Room-type table (list of configured room types with edit/remove)
- Add/edit detail experience
- Quantity and occupancy rules
- Conditional room-number requirements
- Amenities, photos, and policies
- A completion contract
- Dependency invalidation when rooms or capacities change

## Existing code to reuse

| Need | Reuse |
|---|---|
| Save a room type | `HotelPortal::RoomTypes::SaveRoomType` (`app/services/hotel_portal/room_types/save_room_type.rb`) |
| Remove a room type | `HotelPortal::RoomTypes::DestroyRoomType` |
| Photo removal | `HotelPortal::RoomTypes::DestroyPhotos` |
| Existing form/UI reference | `app/controllers/hotel_portal/room_types_controller.rb` and its views |

`RoomType` records are saved directly — there is no form object layer. Do not create
onboarding-only room records; these are the real operational rooms.

## Things to watch in `SaveRoomType`

Read `app/services/hotel_portal/room_types/save_room_type.rb` before wiring it up. Three
behaviours matter:

1. **It advances legacy hotel status.** `@hotel.complete_rooms! if is_new_record` writes the
   legacy `rooms_incomplete` status. Per the shared rules, leave this alone — Phase 13
   removes it. Just be aware that creating a room from onboarding will move legacy status,
   and make sure that does not confuse `LifecycleCompatibility.canonical_status`.
2. **It syncs with the channel manager.** `sync_with_channel_manager` fires on save. During
   onboarding no channel manager is connected yet (that is Phase 9), so confirm this is a
   no-op for an unconnected hotel rather than an error path.
3. **It returns an `OpenStruct`, not an `ApplicationResult`.** Your `Onboarding::SaveRoom*`
   wrapper should translate to the `ApplicationResult` shape the shell expects, matching
   `Onboarding::SavePropertyProfile`.

## Suggested services

- `Onboarding::SaveRoomType` — wraps `HotelPortal::RoomTypes::SaveRoomType`, translates the
  result, and does **not** complete the section (adding one room ≠ finishing the step)
- `Onboarding::CompleteRooms` — validates the completion contract across all room types and
  calls `UpdateSection` with `complete`
- `Onboarding::InvalidateDependentSections` — shared helper (see below); if Phase 5 already
  introduced one for tax changes, extend it rather than adding a second

## Completion contract — decide before coding

The plan says "at least one operationally valid room type". Pin down what *valid* means and
record the answer in the handoff doc or a comment. At minimum, confirm with the user:

- Minimum one room type with quantity ≥ 1
- Occupancy must be set (max adults, and children if the hotel supports them)
- When room numbers are required (the "conditional room-number requirements" line) —
  determine the existing trigger in `RoomType` rather than inventing one
- Whether photos and policies are required for completion or only warnings

## Dependency invalidation

Rooms feed `rates_availability` (Phase 7) directly, and occupancy feeds per-pax pricing.
When a completed `rates_availability` section exists and rooms or capacities change, move
it to `needs_attention` via `UpdateSection` with an audit event explaining why. Warn;
do not delete rate or inventory records.

Since Phase 7 does not exist yet when you start, build the invalidation hook now and cover
it with a service spec that drives the section state directly — do not defer it.

## Do not

- Create onboarding-only room tables or duplicate `RoomType` validations
- Initialize any defaults as a side effect of rendering the page
- Add global portal redirects (Phase 12)
- Restructure `RoomTypesController` for the settings portal — leave it working

## Tests

- Service spec: `spec/services/onboarding/rooms_spec.rb` — save, completion contract,
  invalidation of `rates_availability`
- Request spec: extend `spec/requests/hotel_portal/onboarding_spec.rb` — locked section
  before Phase 5 completion, save draft, save & continue, room add/remove authorization
- System spec: extend `spec/system/hotel_portal/onboarding_spec.rb` — owner adds a room
  type and continues
- Responsive review of the room-type table on mobile (`DESIGN.md`)

```bash
bin/test hotel_management
```

## Done when

An owner in `setup` can open the Rooms step, add a valid room type, see it in the table,
edit and remove it, complete the step, and land on `rates_availability`. The `rooms`
section is `complete` with no `placeholder` metadata, and readiness no longer reports it
as blocking.
