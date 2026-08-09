# Rate plan & rate inventory — handover

Branch: `feat/hotel-pricing-policy`. Last updated 2026-08-08.

Scope of this document: **rate plan create** (done), **rate plan edit** (not
started), **rate inventory** (not started). Room category redesign is deferred
and only sketched at the end.

---

## 1. Why this work exists

The setup path — room category → rate plan → rate inventory — was
incomprehensible for three reasons, all still partly true:

1. **The three steps live in three unrelated places, with three different
   names.** Room Categories sits under Settings → Property; Rate Settings under
   Settings → General; Rates & Inventory in the main sidebar, a different shell
   entirely. Nothing on screen says they are one sequence.

2. **A nightly price can come from five places** and nothing shows which one
   won. From `Rates::ResolveEffectiveNightlyPrice`:

   ```
   1  tier price (walk_in / corporate) on the date row
   2  room_rates.price for this plan + date        → :daily_override
   3  room_type_rate_plans.pricing_value (fixed)   → :starting_price
   4  room_types.base_price                        → :room_category_default
   5  the standard plan's date row, x derive       → :standard_daily_rate
   ```

   Per-person mode adds a **second parallel ladder** for `occupancy_prices`
   (daily → assignment → derived-from-standard).

3. **Every screen collected some of the same money.** The rate plan sheet asked
   for per-category prices and a full occupancy matrix; the calendar asks for
   the same things with dates attached.

---

## 2. Decisions already made

Do not relitigate these without a reason; each was argued through.

| Decision | Rationale |
| --- | --- |
| **Sell mode is a hotel-level fact**, mirrored onto rate plans | A property sells one way. `RatePlan#inherit_sell_mode_from_hotel` is the single write point. |
| **Hoteliers cannot change sell mode** — admin only | Flipping it is destructive (see §6). Deliberate, not an oversight. |
| **Create is a wizard; edit is a different screen** | Create serves someone who doesn't know what's needed. Edit serves someone who came to change one thing. Sharing a template would serve neither. |
| **Occupancy matrices are scoped to one room category at a time** | Capacity varies. A matrix spanning categories is either ragged or padded to the property's largest room. |
| **Per-room Derived stays live; per-person Derived/Auto materialise** | Live derivation exists for the scalar case (`pricing_mode` multiplier/offset). There is no schema for a per-occupancy rule, and materialising guarantees a complete matrix. Cost: per-person plans don't track later standard-rate changes. |
| **A partial occupancy matrix is refused at save** | Silently unsellable is worse than a loud refusal (see §6). |
| **No single supplement in per-person** | `Bookings::NightlyPaxPrice` only applies it when no occupancy price exists. "Rate for 1 person" already is the single supplement. |
| **Restrictions, cancellation policy, tax set stay out of the rate plan** | The calendar owns dates and restrictions; policies and taxes live under Settings → Commercial. There is no meal plan / board basis model in the codebase at all. |

---

## 3. What shipped

### Navbar sell-mode badge

```
app/models/hotel.rb                       #sell_mode_label
app/views/layouts/_hotel_shell.html.erb   badge beside the property name
```

`Sells per room` / `Sells per person`, `variant: :outline, size: :sm`,
`hidden md:inline-flex`. Sits beside the identity anchor, not inside it — how a
property sells is a fact about the tenant, not part of the dashboard link.

### Rate plan create wizard

```
config/routes.rb                                        5 routes, before `resources :rate_plans`
app/controllers/hotel_portal/rate_plan_wizards_controller.rb
app/forms/hotel_portal/rate_plan_wizard.rb              session draft, derived steps
app/forms/hotel_portal/rate_plan_wizard/room_pricing.rb one step's validation + matrix
app/services/rate_plans/occupancy_ladder.rb             anchor + step → full matrix
app/services/rate_plans/create_from_wizard.rb           persists, batches the ARI push
app/helpers/hotel_portal/rate_plan_wizards_helper.rb
app/views/hotel_portal/rate_plan_wizards/               show + _steps + 3 step partials + _age_bands
app/javascript/controllers/rate_plan_room_pricing_controller.js
app/views/hotel_portal/settings/_rates_section.html.erb "New rate plan" → wizard
```

Shape:

```
┌─ settings_action_sheet · bottom · full · dismissible:false ──┐
│ New rate plan            Step 2 of 4 · Deluxe twin           │
│ ● Plan details ─ ● Deluxe twin ─ ○ Beachfront suite ─ ○ Review│
│                                                              │
│  [ body: rail + step form ]                                  │
│                                                              │
│ Discard        Back   Apply to all rooms          Next       │
└──────────────────────────────────────────────────────────────┘
     ^ footer buttons bind to the body form via HTML form=""
```

Steps:

```
details    name · description · room categories
           + per_room:   base occupancy, extra pax charge
           + per_person: default child price, age bands
room-<id>  one per selected category, sized to its own max_adults
           per_room   [ Manual | Derived ]
           per_person [ Manual | Derived | Auto ]
review     per-category summary + guest pricing, then Create
```

Behaviour worth knowing:

- **Steps are derived from the selection, never stored.** Untick a category and
  its step and its answers both disappear (`prune_dropped_rooms!`).
- **Deep-linking past a gap redirects to the gap**, so review can never see a
  draft it can't save (`viewable_step?` / `first_incomplete_step`).
- **Nothing is written until review is confirmed.** The draft is session-only
  (cookie store), so an abandoned wizard leaves no rows behind. A few hundred
  bytes for a realistic property; watch it if a property has 20+ categories.
- **Where the money lands:**

  ```
  per_room   Manual   → rtrp.pricing_mode "fixed",  pricing_value = rate
             Derived  → rtrp.pricing_mode multiplier|offset, pricing_value
                        (stays live — resolver derives at read time)
  per_person all      → room_type_rate_plan_occupancy_prices, 1..max_adults
                        rtrp.pricing_mode "fixed", pricing_value nil
  ```

- `Derived` and `Auto` differ only in the anchor: Derived adjusts the
  category's `base_price`, Auto takes a typed rate. Both go through
  `RatePlans::OccupancyLadder`.

### Bug fixes

- **Age-band Add button.** `<template>` used `<% f.fields_for %>` instead of
  `<%= %>`. `fields_for` captures its block and returns the markup, so the
  template rendered empty and the button cloned an empty string. Fixed in
  `rate_plans/_age_bands.html.erb` and the wizard copy. It survived because the
  only age-band system specs run on `rack_test`, which cannot click a JS button
  — the new guards assert the `NEW_RECORD` field name is in the body instead.
- `spec/system/hotel/rate_plan_age_bands_spec.rb` was already red (stale
  heading expectation, fixture plan with no room category). Repaired.

### Test coverage

```
spec/requests/hotel_portal/rate_plan_wizards_spec.rb   19
spec/services/rate_plans/occupancy_ladder_spec.rb       5
spec/requests/hotel_portal/rate_plans_spec.rb          +1 template guard
spec/system/hotel/rate_plan_age_bands_spec.rb           repaired
spec/system/hotel/layout_shell_spec.rb                 +2 badge
```

---

## 4. Rate plan edit — shipped

Edit uses a full bottom action sheet with line tabs, not the earlier proposed
inline-expanding registry. That proposal was never established by the product
decisions and exposed internal words such as “manual” and “derived.”

```
┌─ full bottom sheet ──────────────────────────────────────────┐
│ Non-refundable rate · Price per guest · MYR · Active        │
│ [Plan details] [Rooms and prices 2] [Child pricing]          │
├──────────────────────────────────────────────────────────────┤
│ Rooms rail              │ One focused room-pricing editor    │
│ Deluxe twin       ✓     │ shared with the create wizard      │
│ Garden villa      ⚠     │                                    │
├──────────────────────────────────────────────────────────────┤
│                                      Cancel · Save this tab  │
└──────────────────────────────────────────────────────────────┘
```

Each top-level tab saves independently and remains open after success. Switching
tabs or rooms, closing, or starting a destructive action while the active form
is dirty opens a non-dismissible discard alert. The rooms tab saves only the
selected category; adding a category creates nothing until valid pricing is
saved.

The wizard and editor share both the room-pricing fields and
`RatePlans::SaveRoomPricing`. Per-room adjustments stay live. Per-person
generators fill and materialise a complete direct-price matrix; reopening shows
the stored direct prices because generator provenance is deliberately not
persisted.

Removing a category is handled by `RatePlans::RemoveRoomType`: it refuses the
final category, refuses a matching room/plan pair used by bookings, and deletes
an existing channel-side mapping after commit. Standard Rate uses the same shell
with name and membership locked; its applicable occupancy and child pricing
remain editable.

---

## 5. Next: rate inventory

**Not started.** Ordered by dependency.

```
① Rates::SetupGaps                      query object, no UI. Build first.
   in : hotel, window (default next 90 days)
   out: [{room_type, rate_plan, priced_counts, max_adults, missing_dates}]
   feeds: edit-page row badges · bulk-dialog coverage · nudge strip

② Calendar view filter
   inventory_dashboards#index currently reads room_type_ids only for bulk ops
   and pricing rules — the grid itself has no filter. Add +room_type_ids
   +rate_plan_ids to index, render a removable chip
   ("Deluxe twin · Non-refundable [x]").
   Unblocks: "priced separately" in the rate plan, and the post-create handoff.
   Without it, any handoff link dumps the user on the full grid.

③ Bulk dialog: per-category occupancy blocks
   Today it renders 1..hotel-wide maximum(:max_adults) for every selection,
   and ApplyInventoryDashboardSelection silently drops entries above a
   category's max on save. Replace with one block per selected category:
```

```
│ Adult occupancy prices                                   │
│ Deluxe twin                              [2 pax max]     │
│   Fill from [ 220 ] + [ 100 ] per extra adult   [Fill]   │
│   1 adult [220]   2 adults [320]                         │
│   ✓ all 2 adult counts priced                            │
│ ──────────────────────────────────────────────────────   │
│ Beachfront suite                         [4 pax max]     │
│   1 ad[750] 2 ad[930] 3 ad[1110] 4 ad[1290]              │
│   ✓ all 4 adult counts priced                            │
│ ──────────────────────────────────────────────────────   │
│ Ready to apply to 2 categories.    [Cancel]  [Apply]     │
│                     Apply stays disabled while partial   │
```

```
   Selecting 8 categories renders 8 blocks. That is honest, not a regression —
   the current single grid is only short because it is wrong. If it gets
   unwieldy, cap bulk selection in per-person mode; do not re-merge the grids.

④ Price-origin markers on the calendar
   The resolver already returns `source` as one of daily_override /
   starting_price / standard_daily_rate / room_category_default. Surface it per
   cell with a legend and an "explain this price" popover. Nearly free, and it
   is the thing that finally makes the five-source ladder legible.

⑤ Post-create continuation
   create → offer the next step;  update → toast, stay.
   Rate plan edit offers it too, but only when ① reports a gap.
   Depends on ②, or it lands people on the unfiltered grid.

⑥ Nudge strip on Rates & Inventory
   "2 categories have no prices after 12 Aug — review". Same query as ①.
   Catches everyone who arrived without going through a chain.
```

---

## 6. Open defects — not fixed, decide deliberately

**A partial occupancy matrix makes a room silently unsellable.**
`Rates::ResolveEffectiveNightlyPrice` — once *any* occupancy price exists for a
room type, a missing entry for the requested adult count returns
`amount: nil`, with no fallback. The wizard refuses to create new partials, but
**existing rows are untouched**. Needs a backfill report at minimum. Options:
report and fix by hand · block at model level · fall back instead of nil.
Falling back invents a price nobody chose; nil loses revenue with no trace.

**Flipping `Hotel#sell_mode` is destructive and silent.**
`mirror_sell_mode_to_rate_plans` uses `update_all`, so callbacks are skipped —
no channel resync — and existing `room_rates.occupancy_prices`,
`extra_pax_charge` and age bands stay on disk as dead-but-present data. This is
why hoteliers can't reach the control. Before ever exposing it: name what gets
discarded, and lock it once bookings exist.

**Per-person rate plans never reach channels.** `RatePlan#channex_syncable?` is
false for per-person, because Channex models children as a single flat
property-level fee and has no representation for per-band per-plan pricing.
Availability still syncs; prices and restrictions stay in Wastays. Surfaced in
the wizard's review step, not as a top-of-form banner.

**The walk-in plan is filtered out of the rate list in per-person mode**
(`settings/_rates_section.html.erb`, first line) with no explanation. An island
property just finds walk-in pricing missing.

**`spec/system/hotel/room_setup_spec.rb:19` is red** and was red before this
work — a collapsed-sidebar "Hotel Portal" label, unrelated. Verified by
stashing the layout change and re-running.

---

## 7. Deferred: room category

Not touched. Notes gathered, for whenever it comes up.

The form is 6 sections in 2 columns, read column-major, and the layout comment
says the columns exist because the sections differ in height — so the
arrangement is driven by whitespace, not meaning. It separates things that
belong together: `quantity` sits in the left column while Room Numbering sits
in the right, even though the numbering generator reads `quantity` as its input.

Proposed flattening: **4 sections, single column** — Identity (name, group,
description) → Capacity & rooms (max adults/children, quantity, room numbers)
→ Guest details (amenities, smoking, pets) → Photos.

Also note the sheet sets `dismissible: false` at `size: :full` with a comment
that a stray Esc would discard real work — that is the code conceding it should
be a page.

Vocabulary still drifting across screens:

| Concept | Names in use |
| --- | --- |
| sell mode | "Sells By" (admin) · "How the property charges" (edit sheet) · `charging-model` (Stimulus) · `sell_mode` |
| base price | "Standard Rate" · "Standard rates" · "anchor price" (data attr) |
| base occupancy | "Guests included" · "Base occupancy" · `base_occupancy` |

Keep the industry terms — pax, single supplement, base occupancy. It is
"charging model" and "anchor price" that are software-invented and should go.
The wizard already uses the industry terms; the edit sheet does not.
