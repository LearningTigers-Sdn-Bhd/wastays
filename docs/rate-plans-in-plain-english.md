# Rate plans in plain English

Last reviewed against the product on 2026-08-10.

Who this is for: anyone who explains, tests, or supports room and rate setup.
The implementation details are in
`docs/rate-plan-and-inventory-handover.md`.

## The two places to remember

Pricing work is split between two connected screens:

| Screen | What it answers |
| --- | --- |
| **Settings → Property → Room Inventory** | Which rooms exist, which offers apply to them, and what do those offers normally cost? |
| **Rates & Availability** | What changes on particular dates? |

Room Inventory is the standing setup. Rates & Availability is the calendar for
daily prices, availability, restrictions, and exceptions.

If a sellable rate plan has a valid standing price, the hotel does not need a
separate price row for every future date. The calendar can show and use the
standing price until someone adds a daily override.

## How the property charges

Every property uses one charging model:

- **One price per room** — one nightly room price, with an optional extra charge
  above the number of guests included.
- **Price per guest** — a total nightly room price for each possible number of
  adults, plus child pricing.

This is a property-wide setting, shown beside the property name. Hotel staff
cannot change it themselves because switching models can invalidate existing
prices and channel mappings.

## 1. Start in Room Inventory

Open **Settings → Property → Room Inventory**. Each room category appears as an
expandable row showing its group, capacity, number of rooms, and any rate
issues. Expand a category to see the rate plans guests can book for it.

You can search by room-category or rate-plan name and filter by room group.

From here there are two ways to add a rate:

- **New rate** on one room category: configure one plan and its price for that
  category.
- **Assign → Assign Room Rate** at the top of the page: attach one reusable rate
  plan to several categories quickly.

These actions solve different jobs.

## 2. New rate — configure one room completely

Click **New rate** inside an expanded room category. A right-side sheet opens.
It always configures one room category at a time.

### Choose the room and rate plan

The room is preselected when the sheet was opened from that room's row, but it
can be changed.

In **Rate plan name**, either:

- choose an existing custom rate plan from the suggestions; or
- type a new name, such as “Non-refundable” or “Long stay.”

Choosing an existing plan reuses its shared name, description, occupancy, and
child-pricing rules. The sheet then configures only this room category's price.

Typing a new name creates a reusable custom plan. Its description and shared
guest-pricing rules are saved with it.

### Set the standing price

For a property charging **one price per room**, choose either:

- a direct standing price;
- a percentage adjustment from Standard Rate; or
- an amount adjustment from Standard Rate.

An adjusted price stays live. For example, a plan set to 10% below Standard
Rate follows later Standard Rate changes unless a daily calendar price overrides
it.

For a property charging **per guest**, enter a complete price for every adult
count the room supports, or use one of the helpers:

- **Derived** starts from an adjustment to the room's base price and fills the
  occupancy ladder.
- **Auto** starts from a typed anchor price and fills the ladder by the chosen
  increases or decreases.

Derived and Auto generate real stored prices. They are not live formulas. When
the plan is reopened, the generated values appear as normal editable prices.

The sheet refuses to save an incomplete adult-price ladder.

### Shared child pricing

For a per-guest property, the plan also controls child pricing. You can use one
default child price or define non-overlapping age groups with fixed or
percentage prices.

Child-pricing rules apply everywhere the rate plan is attached. Room capacity
still belongs to each room category.

### What happens when you save

The plan and the selected room's pricing are saved together. If a channel
manager is connected and the plan is compatible, Wastays queues the relevant
rate-plan and rate updates for that room category.

The sheet then closes and returns to Room Inventory.

## 3. Assign Room Rate — reuse a plan across rooms

Use **Assign → Assign Room Rate** when the main job is to attach the same offer
to several room categories.

The sheet asks for:

- an existing custom rate plan or a new plan name; and
- one or more room categories.

It intentionally does not show pricing controls. Each new assignment receives
a safe starting point:

- **Per room:** it initially follows that room's Standard Rate with no
  adjustment.
- **Per guest:** it copies that room's complete Standard Rate occupancy prices.
  Missing Standard values fall back to the room's base price multiplied by the
  adult count.

Open the assigned plan under each room category afterwards when its price
should differ.

Assigning a plan that is already attached does not create a duplicate.

## 4. Editing a rate plan

Expand a room category in Room Inventory and click one of its rate plans. The
right-side editor opens.

The editor has one save action. It shows:

- the selected attached room category;
- the property's charging model and plan currency;
- shared plan details;
- the selected room's pricing;
- child pricing for per-guest properties; and
- archive, restore, or delete actions where allowed.

Changing the room-category selector reloads the same plan for another attached
room. Only the selected room's price is shown and saved, but changes to the
plan's name, description, occupancy rules, or child pricing are shared by every
room using that plan.

Unsaved changes are protected when switching rooms, closing the sheet, or
starting a destructive action.

### Standard Rate

Standard Rate uses the same editor but is protected:

- it cannot be archived;
- its identity cannot be renamed like a custom offer;
- its room assignment cannot be removed as an ordinary custom plan.

For a one-price-per-room property, Standard Rate's standing amount comes from
the room category's default nightly price. Change that amount on the room
category, or use Rates & Availability for specific dates.

### Removing, archiving, and deleting

- **Remove from this room** detaches only that room category. It is refused if
  this is the plan's final room or if bookings use that room-plan combination.
- **Archive** stops a custom plan being offered for new bookings without
  deleting its history.
- **Delete** is available only for eligible custom plans with no booking use.
- System plans such as Standard, walk-in, corporate, and OTA anchors cannot be
  treated like ordinary custom plans.

## 5. Rates & Availability — change specific dates

Open **Rates & Availability** from the main navigation. The calendar shows room
availability and rate-plan prices across dates.

Click a cell to change one night, or widen the editor to several dates, rooms,
or rate plans.

### Changes are staged before saving

Editing a cell does not immediately write to the database:

1. Open a rate or availability cell.
2. Choose the date range and targets.
3. Change only the required fields.
4. Click **Stage update**.
5. Repeat for other changes if needed.
6. Review the pending changes.
7. Click **Confirm Update** to save and synchronize the batch.

Untouched fields are left alone. Pending changes can be reviewed or removed
before confirmation.

### What can be changed

Depending on the row and charging model, the editor can change:

- room price or adult occupancy prices;
- rooms bookable and open/closed status;
- minimum and maximum stay;
- closed to arrival or departure;
- stop sell; and
- channel-specific rates and availability where supported.

For a per-guest local rate, the adult-price fields are sized to the room
category whose cell was opened. Child prices and age groups still come from the
rate plan and are not redefined by date.

### Advanced Pricing

The Advanced Pricing area contains broader tools, including pricing rules,
availability overrides, derived channel pricing, and channel availability
rules.

## 6. Where tonight's price comes from

For a normal rate-plan request, Wastays resolves the first applicable answer:

1. A requested walk-in or corporate tier price, when that special tier applies.
2. A daily calendar price for this room and rate plan.
3. The plan's standing fixed price.
4. A live adjustment from that date's Standard Rate.
5. The same adjustment from the room category's default nightly price when
   Standard Rate has no daily value.
6. Standard Rate or the room category's default nightly price.

Practical translation: a daily calendar price overrides a plan's normal
standing behavior. A derived plan follows Standard Rate until a daily override
is entered for that derived plan.

For per-guest pricing, Wastays also looks for the requested adult count in this
order:

1. that date's occupancy price;
2. the rate plan's stored occupancy price for the room; then
3. a derived Standard Rate occupancy price, where applicable.

Child pricing is added after the adult or room amount is resolved.

## 7. The missing-occupancy trap

If a per-guest room has an occupancy matrix but lacks the requested adult count,
Wastays returns no price instead of inventing a fallback. The room can therefore
disappear from availability for that search.

The current create and edit sheets require complete matrices, and newly
assigned plans are bootstrapped with complete matrices. Older data may still be
incomplete. If a room unexpectedly disappears, check all adult counts supported
by that room category.

## 8. Channel limitation for per-guest plans

Per-guest rate plans are not currently distributed to Channex. Room-category
availability can continue to sync, but the plan's prices and restrictions stay
inside Wastays.

When a connected property creates a per-guest plan, the rate-plan sheet shows
this warning directly.

## Setup order

```text
Room Inventory
  1. Create the room category and set its capacity/default nightly price.
  2. Use New rate to configure one room and offer completely.
  3. Use Assign Room Rate when the offer should be reused by other rooms.

Rates & Availability
  4. Add date-specific prices, availability, restrictions, or pricing rules.
  5. Review staged changes and confirm the batch.
```
