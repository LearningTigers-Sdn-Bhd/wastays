# Phase 7 — Pricing and one-year availability slice

Read `docs/onboarding/handoffs/README.md` first for the shared pattern and rules.

This is the largest and highest-risk phase. Budget accordingly, and consider splitting it
into two commits (pricing, then availability) on the same branch.

## Goal

Make the `rates_availability` section real: a configured room has valid sell-mode pricing
and one year of sellable rates and inventory.

`PLAN.md` §"Phase 7" is the scope authority.

## Prerequisite

`rooms` (Phase 6) must be complete. Room capacities determine the occupancy matrix, so
this phase cannot be designed before rooms are final.

## Two sell modes, two experiences

`Hotel#sell_mode` is immutable after creation (`app/models/hotel.rb:133`) and stores
`per_room` or `per_person`. Note the vocabulary gap: the stored value is `per_person`,
but product wording is **per pax**, and UI copy must keep the hotel-industry terms
(pax, base occupancy, single supplement).

### Per room

- Default room rate
- Base occupancy
- Extra-adult and extra-child pricing
- Rate-plan assignment

### Per pax

- Occupancy matrix sized to the hotel's highest supported occupancy
- Per-room disabled cells above that room's supported occupancy
- Occupancy change warnings
- Child age bands configured once per rate plan
- Responsive one-room-at-a-time mobile experience

## Existing code to reuse

| Need | Reuse |
|---|---|
| System rate plans exist | `RatePlans::EnsureSystemPlans` |
| Initial plan/room assignment | `RatePlans::BootstrapAssignment` |
| Per-room / per-occupancy pricing save | `RatePlans::SaveRoomPricing` |
| Occupancy price matrix generation | `RatePlans::OccupancyLadder` |
| Attach / detach room types | `RatePlans::Attach`, `RatePlans::RemoveRoomType` |
| Records | `RoomTypeRatePlanOccupancyPrice`, `RatePlanAgeBand` |
| Bulk rates | `HotelOps::BulkUpdateRates` |
| Bulk inventory | `HotelOps::BulkUpdateInventory` |
| Both at once | `HotelOps::BulkUpdateRatesAndInventory` |
| Pricing rules | `HotelOps::ApplyPricingRules` |
| UI reference | `app/controllers/hotel_portal/rate_plans_controller.rb`, `rate_plan_room_pricings_controller.rb` |

`RatePlans::OccupancyLadder` carries an important invariant in its own comments: once any
occupancy price exists for a room type, missing counts make the room **silently unsellable**
at those party sizes. Completeness of the ladder is a correctness requirement, not a nicety.
Any onboarding pricing save must materialize every adult count the room can hold.

There is a prior rate-plan wizard effort with standing decisions in
`docs/rate-plan-and-inventory-handover.md`. **Read it before designing this phase** — it
covers the create wizard that already shipped and the edit/rate-inventory work that was
next. Reconcile with it rather than designing a third pricing UI.

## Availability

- Bulk start and end dates, defaulting to one year
- Weekday/weekend rules
- Quantities and open/closed state
- Exceptions
- Coverage calculation
- Expiry warning and extension path

The existing readiness predicate on `Hotel` only checks for a positive rate in the next
30 days (`app/models/hotel.rb:492-496`) and does not verify one-year inventory. The
onboarding completion contract needs its own coverage calculation — do not reuse the
30-day predicate as the bar.

## Open decisions — resolve before coding

From `PLAN.md` §"Open decisions" and `IMPLEMENTATION_MAP.md` §8, these gate this phase:

1. **Is one-year availability a one-time initial population or a maintained rolling
   horizon?** This changes whether coverage is recomputed and re-warned after launch, and
   whether an extension path is onboarding-only or permanent. Ask the user.
2. **Coverage definition.** Channex synchronizes a 500-day horizon
   (`app/services/channel_managers/full_refresh_service.rb`), longer than the one-year
   local target. Define local coverage independently of external sync.

## Extending domain APIs

The plan permits extending the shared rate-plan and inventory domain APIs "only where the
onboarding bulk workflow requires it". If you find yourself adding an onboarding-specific
branch inside `HotelOps::BulkUpdate*`, stop — that is a sign the orchestration belongs in
an `Onboarding::*` service instead.

## Dependency invalidation

Rooms and occupancy changes invalidate this section (built in Phase 6). This section in
turn feeds the commercial phase: discounts target eligible charge codes and payment
surcharges reference extra charges, so a pricing change should warn rather than silently
break those. Extend the shared invalidation helper.

## Tests

- Service specs: pricing per sell mode, occupancy ladder completeness, coverage
  calculation, one-year bulk population, invalidation
- Request specs: both sell modes, locked section, save/continue, validation errors
- System spec: the critical owner path for each sell mode
- Responsive review: the per-pax matrix must degrade to one room at a time on mobile
- Accessibility: matrix cells need labels; disabled cells must be announced as such

```bash
bin/test hotel_management
```

## Done when

For both sell modes, an owner can price every room type completely, populate a year of
rates and inventory, see accurate coverage, and complete the section. A room is not
sellable-with-gaps at any supported party size.
