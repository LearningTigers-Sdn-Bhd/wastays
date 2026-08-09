# Rates and inventory — current status and roadmap

Last reviewed against the implementation on 2026-08-10.

This file tracks the current system and remaining work. It supersedes the
earlier plan built around a multi-room rate-plan wizard, a separate Rate
Settings registry, and a tabbed full-bottom editor. Those interfaces have been
deleted.

## Status legend

- [x] Shipped and represented by the current implementation
- [~] Partially shipped or still missing an important part
- [ ] Not started or still required

## Current product boundaries

- **Room Inventory** owns room categories, room groups, reusable rate-plan
  assignments, and standing prices.
- **Rates & Availability** owns date-specific rates, availability,
  restrictions, pricing rules, and channel rows.
- The **hotel** owns the charging model. Rate plans inherit it.
- A **rate plan** owns shared offer details, occupancy rules, and child-pricing
  rules.
- A **room/rate-plan assignment** owns the standing scalar price rule or adult
  occupancy-price matrix for one room category.
- A **RoomRate** owns date-specific overrides and restrictions.
- A standing price is a fallback, not a request to generate hundreds of future
  daily rows.
- Per-room percentage and amount adjustments remain live.
- Per-person generators materialize complete direct-price matrices.
- Child age bands are plan-wide; capacity remains room-category-owned.
- Per-person pricing is local-only until channel distribution is implemented.

## Staff-facing vocabulary

| Internal concept | Staff-facing wording |
| --- | --- |
| Charging model | How the property charges |
| `per_room` | One price per room / charges per room |
| `per_person` | Price per guest / charges per guest |
| Fixed/manual pricing | Direct price or starting price, according to context |
| Percentage adjustment | Adjust Standard Rate by % |
| Amount adjustment | Adjust Standard Rate by amount |
| Base occupancy | Guests included |
| Extra pax charge | Extra guest charge |
| Single supplement | One-guest surcharge |
| Child price multiplier | Default child price |
| Room/rate-plan relationship | Assigned rate plan |
| Date-specific rate workspace | Rates & Availability |

## Phase 1 — Room Inventory and reusable rate plans

Goal: manage rooms and their sellable offers in one connected workspace.

### Shipped

- [x] Replace the separate Rate Settings registry with
  **Settings → Property → Room Inventory**.
- [x] Show room categories as expandable rows with group, capacity, room count,
  rate issues, and actions.
- [x] Search by room-category or rate-plan name.
- [x] Filter by one or more room groups, including unassigned rooms.
- [x] Create and edit room categories from the same workspace.
- [x] Manage room groups and assign groups to several categories.
- [x] Show attached rate plans beneath each room category.
- [x] Create or configure a plan for exactly one room category in a right-side
  sheet.
- [x] Resolve a free-entry rate-plan name to one existing active custom plan or
  create a new plan.
- [x] Refuse ambiguous duplicate-name resolution.
- [x] Attach one reusable custom plan to several room categories without
  collecting cross-room pricing in the attachment sheet.
- [x] Bootstrap new per-room assignments as a live 0% Standard Rate adjustment.
- [x] Bootstrap new per-person assignments with a complete occupancy matrix.
- [x] Skip relationships that already exist rather than create duplicates.
- [x] Batch channel synchronization for only the newly affected rooms.
- [x] Archive and restore eligible custom plans.
- [x] Keep Standard and special tier plans protected from ordinary destructive
  actions.

### Remaining

- [ ] Decide whether Room Inventory's assignment-level issue count needs a
  direct repair action instead of only opening the editor.
- [ ] Add an auditable report for legacy assignments whose pricing is invalid or
  incomplete.

## Phase 2 — Focused rate-plan create and edit

Goal: configure one room's price without hiding shared plan-wide consequences.

### Shipped

- [x] Redirect old wizard URLs to the current single-room sheet.
- [x] Show the inherited hotel charging model and plan currency as read-only
  context.
- [x] Keep `sell_mode` out of hotel-facing rate-plan parameters.
- [x] Allow the New rate sheet to select either an existing custom plan or a new
  name.
- [x] Preserve an existing selected plan's shared details while configuring the
  selected room assignment.
- [x] Save a newly resolved plan and its first room price in one transaction.
- [x] Replace the tabbed full-bottom editor with one focused right-side sheet.
- [x] Select one attached room category and render only its pricing fields.
- [x] Save shared plan details and the selected room's pricing together.
- [x] Protect dirty state when switching rooms, closing, archiving, or deleting.
- [x] Keep Standard Rate identity locked while allowing applicable pricing
  fields to be maintained.
- [x] Refuse detaching the final room category.
- [x] Refuse detaching a room/plan assignment referenced by bookings.
- [x] Remove a detached assignment's channel mapping after commit.
- [x] Display the per-person channel limitation directly in the create sheet
  for connected properties.

### Remaining

- [ ] Make shared plan-wide fields visually unmistakable when a plan is attached
  to several rooms.
- [ ] Consider showing the affected room count beside shared details and child
  pricing before save.

## Phase 3 — Consistent local pricing

Goal: make rate-plan sheets, the inventory calendar, quotes, bookings, and
financial snapshots resolve the same local price.

### Resolver and persistence shipped

- [x] Use `Rates::ResolveEffectiveNightlyPrice` as the shared local pricing
  boundary.
- [x] Return the effective amount, base room/adult amount, currency, source,
  contributing `RoomRate`, and whether an occupancy matrix supplied the amount.
- [x] Accept preloaded rates and assignments so range callers avoid per-cell
  queries.
- [x] Resolve requested walk-in/corporate tier prices before ordinary plan
  values when that tier applies.
- [x] Let an explicit daily plan price override its standing behavior.
- [x] Persist a fixed per-room standing price on
  `room_type_rate_plans.pricing_value`.
- [x] Derive multiplier/offset plans from that date's Standard Rate and fall
  back to the room category's default nightly price.
- [x] Preserve legacy unattributed daily rows as readable Standard Rate anchors.
- [x] Keep restrictions outside the price formula.
- [x] Apply per-room extra-guest charges in one downstream pricing service.
- [x] Store per-person standing amounts by room assignment and adult count.
- [x] Resolve daily occupancy override → assignment occupancy price → derived
  Standard occupancy price.
- [x] Apply default or age-banded child pricing after resolving the adult amount.
- [x] Keep the one-guest surcharge only as a legacy fallback when an occupancy
  matrix did not provide the adult total.

### Consumers shipped

- [x] Local booking availability.
- [x] Stay-price calculation.
- [x] Booking financial snapshots and repricing.
- [x] AI booking price previews.
- [x] Rates & Availability calendar presentation.
- [x] Restriction-only write paths.

### Remaining

- [ ] Migrate `BookingEngine::RateCalendarService` minimum-price summaries away
  from raw `RoomRate` rows if that endpoint still needs full fallback parity.
- [ ] Make the shared resolver the source for supported channel exports.
- [ ] Audit every remaining direct `RoomRate#price` consumer and document valid
  exceptions.

## Phase 4 — Per-person occupancy and child pricing

Goal: make every supported occupancy explicit and prevent silently incomplete
new configurations.

### Shipped

- [x] Keep `max_adults`, `max_children`, and total capacity on the room category.
- [x] Validate room-category child capacity server-side.
- [x] Enforce capacity during lightweight availability checks and final quote
  allocation.
- [x] Render adult occupancy inputs from 1 through the selected room category's
  `max_adults`.
- [x] Refuse manual create/edit saves with a missing adult count.
- [x] Refuse prices above the category's supported adult count through the form
  boundary.
- [x] Generate complete Derived and Auto matrices through one occupancy-ladder
  service.
- [x] Replace the complete stored matrix atomically when room pricing is saved.
- [x] Bootstrap newly attached per-person plans with a complete matrix.
- [x] Add date-specific occupancy overrides to Rates & Availability.
- [x] Size a clicked calendar cell's occupancy editor to that room category,
  rather than the hotel's largest room.
- [x] Keep child age bands non-overlapping and validate age order.
- [x] Support fixed and percentage age-band pricing.
- [x] Explain that room capacity and plan child pricing have different owners.

### Remaining

- [ ] Build a legacy occupancy-matrix audit/backfill workflow.
- [ ] Decide how to enforce completeness when `room_type.max_adults` changes.
- [ ] Show an example child total for the selected room and adult occupancy.
- [ ] Replace the calendar's shared multi-room occupancy block with one
  capacity-sized block per selected room category, or prevent incompatible
  multi-room selections.

## Phase 5 — Rates & Availability guidance

Goal: make date-specific pricing understandable and lead staff to incomplete
setup before it affects bookings.

### Shipped

- [x] Render local calendar prices through the shared resolver.
- [x] Use charging-model-specific rate editors.
- [x] Separate availability-only editing from rate-plan editing.
- [x] Open cell editors through a server-rendered Turbo Frame.
- [x] Stage several browser-side changes before one confirmed persistence batch.
- [x] Apply only touched fields.
- [x] Support 14-day, 21-day, and month ranges.
- [x] Accept one `room_type_id` and one `rate_plan_id` for server-side calendar
  scoping.
- [x] Preserve relevant inventory state across server-rendered date navigation.
- [x] Keep pricing rules, availability overrides, channel-derived pricing, and
  channel availability rules in Advanced Pricing.

### Partially shipped

- [~] Calendar filtering: single-room/single-plan server-side scoping exists,
  but a complete multi-select filter and removable context chips do not.
- [~] Price-origin information: the presenter retains the resolver's source,
  but cells do not explain or label it.
- [~] Pricing issue visibility: Room Inventory reports assignment-level issues,
  but future date coverage is not audited.

### Remaining

- [ ] Add `Rates::SetupGaps` or an equivalent query with a clearly defined
  coverage window and result contract.
- [ ] Add a direct post-create or post-edit continuation into a scoped Rates &
  Availability view when setup needs date-specific work.
- [ ] Add a Rates & Availability nudge for incomplete future coverage.
- [ ] Add a price-source legend and an accessible “explain this price” detail.
- [ ] Finish the filter UX, including clearing and preserving room/plan context.

## Phase 6 — Channex rate-plan and ARI support

Goal: distribute compatible Wastays pricing correctly instead of treating all
per-person plans as unsupported forever.

### Current state

- [x] Per-room plans can synchronize structure, scalar rates, restrictions, and
  room-level availability.
- [x] Rate-plan create/edit and attachment flows batch ARI work for affected
  rooms.
- [x] Per-person plans are explicitly rejected by
  `RatePlan#channex_syncable?`.
- [x] Connected per-person properties see that availability continues to sync
  while plan prices and restrictions remain in Wastays.

### Remaining

- [ ] Replace the blanket per-person rejection with a capability-based policy.
- [ ] Confirm the current Channex contract for occupancy options, rate units,
  fraction handling, and maximum-stay fields against staging.
- [ ] Create channel rate-plan structures for every supported charging model.
- [ ] Select and document the primary occupancy for external plans.
- [ ] Send scalar daily rates for per-room plans through the shared resolver
  where not already guaranteed.
- [ ] Send occupancy-specific daily rate arrays for supported per-person plans.
- [ ] Define how Wastays age bands map to Channex's flatter child and infant
  pricing model.
- [ ] Choose an explicit fallback for incompatible age-banded plans: flatten,
  OTA-owned child pricing, direct-only, or a separate channel plan.
- [ ] Retire plans that were pushed before `channex_syncable?` narrowed to
  `RatePlan::DISTRIBUTABLE_KINDS`. Walk-in and corporate plans are now excluded,
  but nothing deletes what was already sent — those plans keep their
  `channel_mapping` and simply stop receiving updates, so the rates left live on
  the channel drift. `delete_from_channel_manager` only fires on destroy.
- [ ] Make sync results distinguish full success, availability-only success,
  unsupported pricing, and failure.
- [ ] Add contract specs for scalar and occupancy-specific structure and ARI
  payloads.

## Phase 7 — Charging-model transitions

Goal: make switching between per-room and per-person safe for connected and
unconnected properties.

### Current risk

`Hotel#mirror_sell_mode_to_rate_plans` uses `update_all`. It keeps stored plan
values aligned with the hotel but skips rate-plan callbacks and does not
reconcile data whose meaning changes with the charging model.

### Remaining

- [ ] Replace callback-only mirroring with an explicit transition service.
- [ ] Detect active channel-manager connections before changing the model.
- [ ] Inventory the scalar prices, occupancy matrices, daily occupancy
  overrides, extra-guest charges, one-guest surcharges, and age bands affected
  by the transition.
- [ ] Define which values are transformed, retained as inactive history, or
  deleted.
- [ ] Preserve valid room/rate-plan assignments.
- [ ] Reconcile or recreate external rate-plan structures and channel mappings.
- [ ] Push a complete availability, rate, and restriction snapshot after a
  successful transition.
- [ ] Report partial failure and provide a retry path.
- [ ] Prevent a generic success result when only availability synchronized.
- [ ] Decide whether `rate_plans.sell_mode` should remain duplicated or be
  derived from the hotel everywhere.
- [ ] If it remains, add a database-level consistency guarantee and repair
  existing mismatches.
- [ ] Cover connected transitions in both directions end to end.

## Current implementation map

### Room Inventory and assignment

```text
app/controllers/hotel_portal/room_types_controller.rb
app/controllers/hotel_portal/rate_plan_attachments_controller.rb
app/queries/room_types_query.rb
app/services/rate_plans/resolve.rb
app/services/rate_plans/attach.rb
app/services/rate_plans/autocomplete.rb
app/services/rate_plans/bootstrap_assignment.rb
app/views/hotel_portal/room_types/
app/views/hotel_portal/rate_plan_attachments/
```

### Rate-plan pricing

```text
app/controllers/concerns/rate_plan_editor_loading.rb
app/controllers/hotel_portal/rate_plans_controller.rb
app/controllers/hotel_portal/rate_plan_room_pricings_controller.rb
app/forms/hotel_portal/rate_plan_room_pricing.rb
app/services/rate_plans/save_room_pricing.rb
app/services/rate_plans/remove_room_type.rb
app/services/rate_plans/occupancy_ladder.rb
app/views/hotel_portal/rate_plans/
```

### Effective pricing and inventory

```text
app/services/rates/resolve_effective_nightly_price.rb
app/services/bookings/nightly_pax_price.rb
app/controllers/hotel_portal/inventory_dashboards_controller.rb
app/services/hotel_portal/inventory_calendar_presenter.rb
app/services/hotel_ops/apply_inventory_dashboard_selection.rb
app/views/hotel_portal/inventory_dashboards/
app/javascript/controllers/inventory_calendar_controller.js
```

## Open findings from the system-plan review

Raised while reviewing the change that turned the virtual walk-in/corporate
tiers into real rate plans (2026-08-10). The data-safety and correctness items
from that review are fixed; these were deliberately left open.

- [ ] **Decide whether the public rate calendar still shows corporate pricing
  for a partner code.** `BookingEngine::RateCalendarService` used to resolve a
  partner from `@partner_code` and take
  `LEAST(price, COALESCE(corporate_price, price))`. Materializing the tiers
  dropped both, and `@partner_code` is now an unused ivar the caller still
  passes. This is a product call, not a cleanup: either rebuild it against the
  corporate rate plan, or remove the parameter so the calendar is honestly
  public-only.
- [ ] **Give a new per-person category a Standard occupancy ladder.**
  `RatePlans::EnsureSystemPlans` creates the standard assignment directly, while
  walk-in and corporate go through `RatePlans::BootstrapAssignment`, which
  materializes a full ladder. On a per-person hotel a fresh category therefore
  shows Standard as "Needs pricing" while the two tiers read "Ready". Cosmetic,
  but it points the operator at the wrong row.
- [ ] **Reconsider the rate-plan fallback when the room category changes.**
  `Bookings::UpdateStayService` keeps `current_room.rate_plan` when only the room
  type changes, so a stay can end up on a plan that is not assigned to the new
  category. An explicitly picked rate that no longer resolves now fails loudly;
  this path still does not.

## Recommended next slice

1. [ ] Implement a read-only legacy pricing audit covering incomplete
   per-person matrices and missing room/rate-plan standing prices.
2. [ ] Define the expected future-coverage window and turn that audit into the
   setup-gap query used by Room Inventory and Rates & Availability.
3. [ ] Add scoped continuation and nudge UI only after the query contract is
   stable.
4. [ ] Complete multi-room per-person bulk editing without assuming every room
   has the same adult capacity.
