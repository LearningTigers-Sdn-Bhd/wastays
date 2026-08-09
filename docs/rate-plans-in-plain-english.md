# Rate plans in plain English

Who this is for: anyone who has to explain, test, or support the pricing
screens. No code knowledge assumed. The mechanics behind it are in
`docs/rate-plan-and-inventory-handover.md`.

---

## The one idea to hold on to

There are **two kinds of pricing work**, and they live in two different places
for a good reason:

| | Where | Answers |
| --- | --- | --- |
| **Rate plan** | Settings → Rates | "What is this deal, and what does it normally cost?" |
| **Rate calendar** | Rates & Inventory | "What does it cost *on these particular dates*?" |

A rate plan is the **standing price list**. The calendar is the **exceptions
list**: school holidays, a quiet Tuesday, a stop-sell weekend.

If you only ever set up a rate plan and never touch the calendar, the hotel
still sells — every night just uses the standing price. That is the intended
behaviour, not a gap.

### How the property charges — set once, for the whole property

Every property is either **per room** ("MYR 300 a night for the room, however
many of you are in it") or **per person** ("MYR 150 per adult per night"). This
is a property-wide fact — you can see it as a badge next to the property name in
the top bar. Hoteliers cannot flip it themselves; support/admin does, because
changing it invalidates prices already entered.

Everything below behaves differently depending on which one you are.

---

## 1. Creating a rate plan — the wizard

**Settings → Rates → New rate plan.** A full-screen panel opens with a progress
strip along the top. Nothing is saved until the very last click; abandoning
halfway leaves no mess behind.

### Step 1 — Plan details

Name it ("Non-refundable", "Long stay"), describe it, and tick **which room
categories it applies to**. A plan doesn't have to cover every room.

Also here, depending on how the property charges:

- **Per room:** base occupancy ("price includes 2 pax") and the extra pax charge.
- **Per person:** the default child price and age bands (e.g. 0–3 free, 4–11 half).

### Steps 2..n — one step per room category

This is the part that makes the wizard long, and it is deliberate. A beach suite
that sleeps 4 and a twin room that sleeps 2 cannot share one price grid, so each
category gets its own step, sized to its own capacity.

On each step you pick how the price is decided:

- **Manual** — you type the number. Most common, most predictable.
- **Derived** — "always 10% below the Standard Rate", or "MYR 50 above it".
  Per room, this stays *live*: change the standard rate later and this plan
  follows automatically.
- **Auto** (per-person only) — you give one anchor price and a step ("MYR 220 for
  1 adult, +MYR 100 per extra adult") and the system fills the whole grid.

A shortcut button copies the current step's answers to the remaining categories.

Important quirk of per-person: Derived and Auto **fill in real numbers once, now**
— they don't keep tracking the standard rate afterwards. If you reopen the plan
later you'll see plain typed prices, not the rule you used. That's on purpose:
a half-filled price grid makes a room unsellable, so the system guarantees a
complete grid instead of a live formula.

### Final step — Review

A per-category summary of everything, then **Create**. If a per-person grid is
incomplete (say 1 and 3 adults priced but not 2), the wizard refuses to save.
Loud refusal beats a room that quietly stops appearing in search results.

If the plan is per-person, review also warns that **prices for this plan won't
reach OTA channels** — the channel connection has no way to express per-person
pricing. Availability still syncs; the prices stay inside Wastays.

### What happens on Create

The plan is written, each room category gets its price (or price grid), and one
batched update is pushed to the channel manager.

---

## 2. Editing a rate plan — the tabbed sheet

**Settings → Rates → click a plan.** A different screen on purpose: the wizard
serves someone who doesn't know what's needed yet, edit serves someone who came
to change one specific thing.

A bottom sheet opens with three tabs:

| Tab | What's in it |
| --- | --- |
| **Plan details** | Name, description, base occupancy / extra pax — the plan-wide settings |
| **Rooms and prices** | A list of room categories down the left; click one, edit its prices on the right |
| **Child pricing** | Default child price and age bands |

Rules that surprise people the first time:

- **Each tab saves on its own.** "Save" saves the tab you're looking at, and the
  sheet stays open. There is no one big save at the end.
- **The rooms tab saves one category at a time** — the one selected in the left
  rail, not all of them.
- **Unsaved changes are protected.** Switching tabs, switching rooms, or closing
  with unsaved edits pops a confirm-discard prompt you have to answer.
- A ⚠ next to a room in the rail means its prices are incomplete.
- **Adding a room category creates nothing** until you save valid prices for it.
- **Removing a room category is refused** if it's the last one, or if that
  room + plan combination is already on a booking. If it was mapped to a channel,
  the mapping is removed too.
- **Standard Rate** uses the same sheet, but its name and room membership are
  locked — it's the anchor everything else can be derived from.

The price editor itself is literally the same component the wizard uses, so
Manual / Derived / Auto behave identically here.

---

## 3. Changing prices for specific dates — the rate calendar

**Rates & Inventory** in the main sidebar. A grid: room categories and rate plans
down the side, dates across the top. Each cell is one room + one plan + one night.

### The staging model

This is the single most important thing to understand about the calendar:
**editing a cell does not save anything.** Changes pile up as a draft.

1. **Click a cell** (or **Bulk edit** for a date range across many rooms/plans).
   A dialog opens showing what's currently there.
2. Change what you want — price, occupancy prices, room quantity, open/closed,
   min/max stay, closed-to-arrival, closed-to-departure, stop-sell.
3. **Stage Update.** The dialog closes; affected cells get highlighted with a dot.
   Still nothing saved to the database.
4. Repeat as many times as you like. The draft survives a page refresh (it's kept
   in the browser), and a counter shows how many pending changes you have.
5. **Review** lists every staged change in words; anything can be removed here.
6. **Sync / Save.** Now everything is written at once, in one transaction, and
   one channel-manager push goes out for the affected dates.

Only the fields you actually touched are applied — untouched fields on the
dialog are left alone rather than overwritten with blanks.

### Bulk tools (the "Advanced" tab)

Beyond cell-by-cell, there are rule-based tools:

- **Pricing rules** — general price, weekend price (you pick which days count),
  school holidays, public holidays, walk-in and corporate tiers, each with its
  own date window. Applied across selected room categories in one go, and
  re-applied automatically if you later delete a rule.
- **Availability override** — set room quantity or open/close a date range.
- **Channels & OTAs** — per-channel rates and availability, where a channel is
  connected.

### What a calendar price actually overrides

A calendar entry is the **most specific** answer for that room + plan + date, so
it wins over everything the rate plan says. That's the whole point of it.

---

## How the three fit together — where a nightly price comes from

When the system needs "what does this room cost on 14 August for this plan?", it
walks down this list and takes the first answer it finds:

1. **A walk-in or corporate tier price** on that date — the most specific.
2. **A calendar price** you set for that plan and date.
3. **The plan's standing price** for that room category (from the wizard/edit sheet).
4. **The room category's own base price** (the fallback in Room Categories).
5. **The Standard Rate's price for that date, adjusted** — for a Derived plan
   like "10% off standard".

Practical translation: *calendar beats plan, plan beats room category.* If a
price on screen isn't what you expected, work down that list — most surprises are
a forgotten calendar entry at level 2 sitting on top of a correct plan price.

Per-person properties run a second, parallel version of this list for the adult
price grid (calendar grid → plan grid → derived from standard).

### The one trap worth memorising

In per-person mode, if a room has *some* adult counts priced but not all, a
booking request for a missing count returns **no price at all** — the room
silently disappears from availability rather than falling back to something.
New plans can't be created that way any more, but plans created before this rule
existed can still be in that state. If a room "isn't showing up" and nothing
looks wrong, check for a gap in its adult price grid.

---

## The setup order, start to finish

```
Room category   →   Rate plan            →   Rate calendar
(how many pax,      (what the deal is,       (what changes on
 base price)         standing price)          specific dates)

Settings →          Settings →               Rates & Inventory
Property            Rates                    (sidebar)
```

The three steps genuinely are one sequence even though they sit in three
different parts of the app under three different names. That's a known rough
edge, not something you're missing.
