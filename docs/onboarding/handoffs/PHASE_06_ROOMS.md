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

- Room-type `HotelPortal::Setup::RecordTable` (list of configured room types with
  leading remove and trailing room-numbering action)
- Inline spreadsheet add/edit experience
- Quantity and occupancy rules
- Conditional room-number requirements
- Staged Amenities and room-number action sheet
- Smoking and pet policies
- A completion contract
- Dependency invalidation when rooms or capacities change

## Existing code to reuse

| Need | Reuse |
|---|---|
| Save a room type | `HotelPortal::RoomTypes::SaveRoomType` (`app/services/hotel_portal/room_types/save_room_type.rb`) |
| Remove a room type | `HotelPortal::RoomTypes::DestroyRoomType` |
| Existing form/UI reference | `app/controllers/hotel_portal/room_types_controller.rb` and its views |
| Onboarding record table | `HotelPortal::Setup::RecordTable` and its Staff/Taxes usages |

`RoomType` records are saved directly — there is no form object layer. Do not create
onboarding-only room records; these are the real operational rooms.

## Record table and detail workflow — decided

Use `HotelPortal::Setup::RecordTable` for the Rooms collection. Do **not** create a raw
`PanelsUI::Table` with a second page-local mobile-card rendering.

Extend `RecordTable` with a backward-compatible spreadsheet mode:

- Keep the existing inline cloneable-row mode unchanged for Staff and Taxes.
- Let the footer Add action clone an inline room row.
- Let the leading `Remove` control discard new rows or stage persisted rows for confirmed
  deletion on the next table save.
- Add the optional trailing `Actions` column defined by `DESIGN_DECISIONS.md`; its direct
  action opens room numbering.
- Keep empty state, keyboard behaviour, focus handling, sticky identifying columns, and
  horizontal overflow owned by the shared component.

The table directly edits name, adult capacity, child capacity, total rooms, no-smoking,
and no-pets. Amenities is a count button opening the shared client-staged action sheet.
The trailing Actions cell opens room numbering, where numbers render as `xs` badges.
Descriptions, photos, room groups, and pricing are intentionally deferred; new rooms use
an internal zero base price until Phase 7 establishes valid pricing.

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

- `Onboarding::SaveRooms` — saves the full spreadsheet atomically through the existing
  room save/destroy services and applies the page completion contract
- `Onboarding::InvalidateDependentSections` — shared helper (see below); if Phase 5 already
  introduced one for tax changes, extend it rather than adding a second

## Completion contract — decided

`Onboarding::CompleteRooms` validates every persisted room type, not merely the first:

- At least one room type exists.
- Every room type has quantity ≥ 1, `max_adults` ≥ 1, `max_children` represented with
  zero allowed.
- Quantity-only inventory is valid. Room numbers are optional; when any are supplied,
  they must be nonblank, unique, and total exactly the room quantity.
- Amenities, smoking policy, and pet policy are optional and do not block completion.
- Pricing is not part of this section's completion contract.

Reject invalid numbering before persistence. A failed save or completion must leave the
section state unchanged and return field/page-level errors.

## Dependency invalidation

Rooms feed `rates_availability` (Phase 7) directly, and occupancy feeds per-pax pricing.
When a completed `rates_availability` section exists and rooms or capacities change, move
it to `needs_attention` via `UpdateSection` with an audit event explaining why. Warn;
do not delete rate or inventory records.

Since Phase 7 does not exist yet when you start, build the invalidation hook now and cover
it with a service spec that drives the section state directly — do not defer it.

Structural mutations are add, remove, quantity, adult/child occupancy, numbering mode,
and room-number changes. If Rooms was complete, a structural mutation moves it to
`needs_attention` for reconfirmation; if `rates_availability` was complete, move that
section to `needs_attention` too. Description, amenity, photo, smoking, and pet-policy
changes preserve both completion states. Every invalidation carries an explanatory audit
event, and none deletes or rewrites rates or inventory.

## Do not

- Create onboarding-only room tables or duplicate `RoomType` validations
- Add rate, rate-plan, pricing, availability, description, photo, or room-group UI
- Initialize any defaults as a side effect of rendering the page
- Add global portal redirects (Phase 12)
- Restructure `RoomTypesController` for the settings portal — leave it working
- Introduce a `HotelPortal::Onboarding` module. It shadows the top-level `Onboarding`
  domain constant inside `HotelPortal::OnboardingController`. Use a flat portal
  controller name such as `HotelPortal::OnboardingRoomTypesController` for sub-resources.

## Tests

- Service spec: `spec/services/onboarding/rooms_spec.rb` — save, completion contract,
  invalidation of `rates_availability`
- Request spec: extend `spec/requests/hotel_portal/onboarding_spec.rb` — locked section
  before Phase 5 completion, save draft, save & continue, room add/remove authorization
- System spec: extend `spec/system/hotel_portal/onboarding_spec.rb` — owner adds a room
  type and continues
- Responsive review of the room-type table on mobile (`DESIGN.md`)
- Component specs for the backward-compatible spreadsheet `RecordTable` API, including
  inline add, deferred confirmed removal, trailing action slot, sticky columns, and
  contained horizontal overflow

```bash
bin/test hotel_management
```

## Done when

An owner in `setup` can open the Rooms step, add a valid room type, see it in the table,
edit and remove it, complete the step, and land on `rates_availability`. The `rooms`
section is `complete` with no `placeholder` metadata, and readiness no longer reports it
as blocking.

## Current implementation state

Phase 6 is implemented as the rooms-only spreadsheet described above. The shared
`RecordTable` extension remains backward compatible with Staff and Taxes, while Rooms
uses the opt-in spreadsheet mode and the client-staged amenities and numbering sheet.
Rates, pricing, rate plans, availability, descriptions, photos, and room groups remain
outside this phase.
