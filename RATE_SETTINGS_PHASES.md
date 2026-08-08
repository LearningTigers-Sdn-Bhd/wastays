# Rate Settings and Inventory Implementation Checklist

Last updated: 2026-08-08

## Status legend

- [x] Complete
- [ ] Not started or still required
- [~] Deliberately deferred to a later phase

## Agreed product decisions

- [x] The hotel is the operator-controlled source of truth for how the property charges: one price per room or price per guest.
- [x] A rate plan does not expose its own charging-model selector.
- [x] Staff-facing screens use familiar hotel language. Technical terms such as `sell_mode`, `rate_mode`, `manual`, `derived`, `multiplier`, and `offset` stay internal.
- [x] Wastays does not need to copy the Channex form. Wastays collects hotelier decisions and translates them into Channex payloads in the integration layer.
- [x] Daily prices, availability, and restrictions remain date-based operations under Rates & Availability.
- [x] UI verification in this workspace uses request tests, source-level accessibility checks, and lint. Do not use browser tools or plugins for testing.

## Agreed staff-facing vocabulary

| Internal concept | Staff-facing wording |
| --- | --- |
| Charging model | How the property charges |
| `per_room` | One price per room |
| `per_person` | Price per guest |
| Fixed/manual pricing | I'll set prices by date |
| Percentage adjustment | Adjust Standard Rate by % |
| Amount adjustment | Adjust Standard Rate by amount |
| Base occupancy | Guests included |
| Extra pax charge | Extra guest charge |
| Single supplement | One-guest surcharge |
| Child price multiplier | Default child price |
| Room categories and pricing | Rooms and prices |

## Phase 1 — Rate-plan sheet correctness

Goal: make the sheet understandable and safe for hotel staff without changing the underlying pricing engine.

### Completed

- [x] Show the inherited charging model as read-only context.
- [x] Show the plan currency as read-only context.
- [x] Initialize a new plan with the hotel's default currency.
- [x] Keep the sell-mode selector out of the rate-plan sheet and strong parameters.
- [x] Use mode-specific sections:
  - [x] One price per room: guests included and extra guest charge.
  - [x] Price per guest: one-guest surcharge and default child price.
- [x] Apply the agreed staff-facing vocabulary to pricing choices and descriptions.
- [x] Explain that prices set by date belong under Rates & Availability.
- [x] Keep live adjustment previews and announce preview changes accessibly.
- [x] Require at least one room category for every custom rate plan.
- [x] Roll back an update that attempts to remove the final room category.
- [x] Show the room-selection error next to the room list and associate it with the checkboxes.
- [x] Show connected price-per-guest properties the current distribution limitation: availability syncs, while prices and restrictions remain in Wastays.
- [x] Cover inherited context, friendly labels, selection validation, rollback behavior, and distribution messaging with request specs.

### Verification completed

- [x] Focused Phase 1 request suite: 33 examples, 0 failures.
- [x] Broader related suite: 123 examples, 0 failures.
- [x] Targeted RuboCop: no offenses.
- [x] `git diff --check`: clean.

### Deferred to Phase 2

- [~] Add a persisted starting price for plans where staff choose "I'll set prices by date."
- [~] Add per-guest occupancy price previews.
- [~] Decide the date range initialized by a starting price; do not invent or duplicate a pricing horizon in the sheet.

## Phase 2 — One consistent local pricing engine

Goal: ensure the rate-plan sheet, inventory calendar, booking quotes, bookings, and future channel exports calculate the same effective price.

### Prepared implementation approach

Phase 2 will be delivered in small, independently testable slices. The shared
resolver comes first; UI changes only follow after booking and calendar callers
use the same result.

#### Shared resolver contract

- [x] Trace the existing sheet, calendar, availability, quote, booking snapshot,
  restriction-write, preview, and future channel-export pricing paths.
- [x] Define the shared service boundary: `Rates::ResolveEffectiveNightlyPrice`.
- [x] Add a result object that exposes at least:
  - [x] the effective nightly amount for the requested occupancy;
  - [x] the underlying adult/room amount before occupancy charges;
  - [x] currency;
  - [x] source (`daily_override`, `standard_daily_rate`, `starting_price`, or
    `room_category_default`);
  - [x] the effective `RoomRate`, when one supplied daily values.
- [x] Accept a room category, rate plan, date, currency, adults, children,
  child ages, and optional rate tier.
- [x] Allow callers with preloaded rates and room-plan assignments to pass them
  in, so calendar and availability ranges do not introduce per-cell queries.
- [x] Keep booking eligibility restrictions outside the price formula. A
  restriction may block sale, but must not independently change the amount.

#### Effective-price precedence

Use this precedence consistently for every caller:

1. An explicit daily price for the selected room category and rate plan wins.
2. A requested walk-in or corporate tier on the Standard Rate row wins for that
   tier.
3. A fixed plan uses its persisted starting price when no daily price exists.
4. A percentage or amount adjustment derives from that date's Standard Rate;
   when the date has no Standard Rate row, it derives from the room category's
   default nightly price.
5. The Standard Rate falls back from its daily row to the room category's
   default nightly price.
6. Legacy unattributed daily rows remain readable as Standard Rate anchors
   until the data is cleaned up.

After the underlying adult/room amount is resolved, apply occupancy pricing in
one place:

- One price per room: add the extra guest charge only above guests included.
- Price per guest: charge each adult, apply age-band or default child pricing,
  and add the one-guest surcharge only when total occupancy is one.

#### Persisted starting price

- [x] Choose the storage approach: use the existing
  `room_type_rate_plans.pricing_value` for fixed plans as that room category's
  starting price; do not create hundreds of future `RoomRate` rows.
- [x] Require a non-negative starting price for newly created or edited fixed
  assignments.
- [x] Preserve compatibility for existing fixed assignments with a blank value
  by falling back to the room category's default nightly price until edited.
- [x] Add one starting-price input per selected room category in the rate-plan
  sheet.
- [x] Treat a daily `RoomRate` as an override of the starting price for that
  date only.

#### Delivery slices

1. [x] Add the resolver and focused unit specs for precedence, currency,
   adjustment floors, occupancy, child age bands, and daily overrides.
2. [x] Refactor `Bookings::CalculateStayPrice`, booking availability, and
   financial snapshots to use it; delete duplicated calculations only after
   regression parity is proven.
   - [ ] Migrate the public `BookingEngine::RateCalendarService` minimum-price
     endpoint, which still summarizes raw `RoomRate` rows.
3. [x] Refactor the inventory calendar presenter and restriction-only writes to
   use it, including derived prices and fixed starting prices.
4. [x] Add the starting-price and occupancy previews to the rate-plan sheet,
   using the agreed staff-facing vocabulary.
   - [x] Starting-price and adjusted-price previews.
   - [x] Complete per-guest occupancy inputs and capacity context.
5. [x] Make inventory editing mode-specific and remove irrelevant inputs.
6. [ ] Expose the resolver as the only local price source consumed by Phase 3
   channel export.

#### Known inconsistencies found during preparation

- [x] The inventory calendar currently shows the room category default when an
  adjusted plan has no explicit daily row, while bookings derive from the
  Standard Rate for that date.
- [x] Nightly resolution is duplicated across booking availability,
  `Bookings::CalculateStayPrice`, and financial snapshot creation.
- [x] `Bookings::CalculateStayPrice` does not consistently constrain fallback
  `RoomRate` lookup by currency.
- [x] Restriction-only writes contain a separate copy of derived-price fallback
  logic.
- [x] The AI booking preview only prices dates that already have complete
  `RoomRate` rows, so it cannot represent every fallback the booking engine can.
- [x] Daily occupancy overrides currently exist for both charging models, even
  when some fields are irrelevant to the hotel's charging model.

#### Phase boundary

- Phase 2 changes local pricing only. It does not enable price-per-guest Channex
  distribution or change external payloads.
- Channel-specific markups remain separate from the hotel's effective local
  price. Phase 3 applies them, if retained, after the local price is resolved.
- No browser or plugin testing will be used in this workspace.

#### Preparation baseline

- [x] Existing focused pricing and inventory regression suite: 109 examples,
  0 failures.

#### Current Phase 2 verification

- [x] Shared resolver and cross-consumer consistency specs added.
- [x] Focused pricing, booking, inventory, preview, model, and request suites:
  188 examples, 0 failures after the occupancy-matrix and child-pricing changes.
- [x] Booking-domain regression: 932 examples, 0 failures.
- [x] Channel-manager regression: 70 examples, 0 failures.
- [x] Targeted RuboCop: no offenses.

### Pricing behavior

- [x] Establish one service that resolves the effective nightly price for a room category, rate plan, date, currency, and occupancy.
- [~] Reuse the service in booking availability, stay pricing, rate previews, and channel export.
  - [x] Local booking availability, stay pricing, financial snapshots, AI price previews, and inventory calendar.
  - [ ] Channel export is implemented in Phase 3.
- [x] Make percentage and amount adjustments follow the room category's Standard Rate on every date.
- [x] Preserve an explicit daily override when staff replace an adjusted price for a specific date.
- [x] Ensure restrictions applied to an unpriced date do not silently change its effective price.
- [x] Define and persist the starting-price behavior for "I'll set prices by date."

### Inventory experience

- [x] Make the rate inventory calendar display the same adjusted price used by bookings.
- [x] One price per room: show only room price, guests included, and extra guest charge.
- [x] Price per guest: show one total nightly price for every supported adult occupancy and applicable child-pricing information.
- [x] Remove base-occupancy and extra-pax inputs from price-per-guest inventory editing.
- [x] Add clear effective-price previews for each selected room category.
- [x] Add occupancy previews for price-per-guest plans when an adult nightly price is available.

### Occupancy capacity and per-guest price matrix

- [x] Keep capacity owned by each room category: maximum adults and maximum
  children are not editable on a rate plan.
- [x] Add server-side validation that maximum children is a non-negative whole
  number; the room-category form currently requires it but the model does not.
- [x] Make lightweight hotel/API availability checks enforce maximum adults,
  maximum children, and total capacity, matching final quote allocation.
- [x] In each selected room-category row, show its adult and child capacity as
  read-only context.
- [x] For price-per-guest properties, generate one editable starting-price row
  for every valid adult occupancy from 1 through that room category's maximum
  adults.
- [x] Do not allow staff to add an adult occupancy above the room category's
  maximum adults.
- [x] Persist occupancy prices per room-category/rate-plan assignment rather
  than as one global adult unit price.
- [x] Add matching date-specific occupancy overrides to Rates & Availability.
- [x] Update the effective-nightly-price resolver to select the requested adult
  occupancy price before applying child pricing.
- [x] Retain the current adult-unit-price formula only as a documented legacy
  fallback during migration.

### Child pricing and age-group discoverability

- [x] Put a clearly labeled "Child pricing" section directly after adult
  occupancy prices in every price-per-guest rate-plan sheet.
- [x] Explain that the room category controls how many children are allowed,
  while the rate plan controls what permitted children cost.
- [x] Provide two clear choices:
  - [x] Use one default child price for every age.
  - [x] Set different prices by age group.
- [x] Keep an always-visible "Add age group" action when age-group pricing is
  selected; do not rely on a low-prominence empty state.
- [x] Use staff-facing labels: age group name, youngest age, oldest age, and
  nightly child price.
- [x] Allow each age group to use either a fixed nightly amount or a percentage
  of the selected adult occupancy price.
- [x] Reject an oldest age below the youngest age.
- [x] Reject overlapping age groups within the same rate plan.
- [x] Show uncovered ages explicitly as using the default child price.
- [ ] Show an example child total for the currently selected room category and
  adult occupancy.
- [x] Keep age-group definitions in Rate Settings. The inventory timeline may
  preview the computed child amount but does not redefine age ranges by date.

### Phase 2 acceptance checks

- [x] The sheet, calendar, quote, and booking totals agree for fixed prices.
- [x] The sheet, calendar, quote, and booking totals agree for percentage adjustments.
- [x] The sheet, calendar, quote, and booking totals agree for amount adjustments.
- [x] Per-room extra guest charges agree across previews and final bookings.
- [x] Per-guest adult, child, and age-group calculations agree across previews and final bookings; legacy one-guest surcharge remains only for plans without an occupancy matrix.
- [x] Focused service, request, and booking regression suites pass.

## Phase 3 — Channex rate-plan and ARI support

Goal: distribute Wastays pricing correctly instead of treating every price-per-guest property as unsupported.

### Rate-plan structure

- [ ] Replace the blanket `per_person` rejection with a capability-based decision.
- [ ] Create Channex rate plans for both one-price-per-room and price-per-guest hotels.
- [ ] Source Channex `sell_mode` from the hotel-level charging model.
- [ ] Initially send Wastays-calculated plans to Channex using `rate_mode: manual` to avoid maintaining two pricing engines.
- [ ] Generate the required Channex occupancy options for price-per-guest plans.
- [ ] Select and document the primary occupancy for each external rate plan.

### Daily ARI payloads

- [ ] Send a scalar daily rate for one-price-per-room plans.
- [ ] Send occupancy-specific daily `rates` arrays for price-per-guest plans.
- [ ] Use the Phase 2 effective-price service to calculate exported prices.
- [ ] Continue to send availability at room-category level.
- [ ] Continue to send min/max stay, closed-to-arrival, closed-to-departure, and stop-sell restrictions.
- [ ] Verify Channex rate units and fraction handling against staging.
- [ ] Verify the current Channex field name for maximum stay; reconcile `max_stay` versus `max_stay_arrival`.

### Child-pricing policy

- [ ] Decide how Wastays age groups map to Channex's flatter child and infant pricing model.
- [ ] Choose one explicit behavior:
  - [ ] Flatten Wastays age groups to a documented channel child fee.
  - [ ] Let each OTA own child pricing while Wastays exports adult occupancy rates.
  - [ ] Mark only incompatible age-banded plans as direct-only.
  - [ ] Maintain a separate channel-compatible rate plan.
- [ ] Show the chosen behavior in staff-facing distribution messaging.

### Phase 3 acceptance checks

- [ ] Contract specs cover Channex rate-plan payloads for both charging models.
- [ ] Contract specs cover scalar and multi-occupancy ARI payloads.
- [ ] Channex staging accepts rates, restrictions, and availability without warnings.
- [ ] The amount displayed in Wastays matches the amount exported for every supported occupancy.
- [ ] Sync results distinguish full success, availability-only success, unsupported pricing, and failure.

## Phase 4 — Sell-mode transitions and reconciliation

Goal: make changes between one-price-per-room and price-per-guest safe for connected properties.

### Transition workflow

- [ ] Replace callback-only mirroring with an explicit hotel charging-model transition service.
- [ ] Detect whether the hotel has an active channel-manager connection before changing the model.
- [ ] Reconcile, replace, or recreate external rate-plan structures when the charging model changes.
- [ ] Preserve valid local rate-plan-to-room-category assignments.
- [ ] Reconcile `ChannelMapping` records with the structures that actually exist remotely.
- [ ] Push a complete availability, rate, and restriction snapshot after the transition.
- [ ] Report partial failures and provide a retry path.
- [ ] Prevent staff from seeing a generic success message when only availability was synchronized.

### Data ownership cleanup

- [ ] Decide whether to remove `rate_plans.sell_mode` and derive it from `Hotel#sell_mode` everywhere.
- [ ] If the duplicated column remains, add a database-level consistency guarantee and reconciliation check.
- [ ] Backfill or repair any plans whose stored value differs from their hotel.

### Phase 4 acceptance checks

- [ ] Connected transition from one price per room to price per guest is covered end to end.
- [ ] Connected transition from price per guest to one price per room is covered end to end.
- [ ] Unconnected transitions remain simple and do not enqueue unnecessary channel work.
- [ ] Failed remote transitions leave an observable, recoverable state.
- [ ] Full related model, service, request, job, and channel regression suites pass.

## Current implementation files

Phase 1 currently changes:

- `app/controllers/hotel_portal/rate_plans_controller.rb`
- `app/helpers/hotel_portal/rate_plans_helper.rb`
- `app/javascript/controllers/room_type_pricing_row_controller.js`
- `app/views/hotel_portal/rate_plans/_form_sheet.html.erb`
- `app/views/hotel_portal/rate_plans/_room_type_pricing.html.erb`
- `spec/requests/hotel_portal/rate_plans_spec.rb`

## Next action

- [ ] Begin Phase 2 by extracting and testing the shared effective-nightly-price calculation before changing more UI or Channex payloads.
