# Boat Transfer — Enablement Considerations

**Written:** 2026-07-29 · **Branch:** `boat-transfer-select`

Two topics:

- **§1–6 — how the feature is gated today**, and the still-open opt-out vs
  opt-in question.
- **§7 — the planned move to `hotel_boat_settings` / `hotel_boat_schedules`**,
  with its decisions locked but nothing built.

A decision record, not a spec. No migration has been written.

---

## 1. What gates the feature today

One per-hotel boolean column. Not a plan, not a feature flag, not a permission.

```
hotels.allow_boat_information   boolean   default: true   null: false
```

| | |
|---|---|
| Who can set it | Platform admin only |
| Where | Admin → Hotels form (`app/views/admin/hotels/_form.html.erb:175`) |
| Also set at creation | `app/forms/admin/hotels/create_form.rb:48` |
| Permitted params | `app/controllers/admin/hotels_controller.rb:99` |
| Default for new hotels | `true` |
| Hotel staff can change it | **No** — `HotelPortal::GeneralSettingsForm` permits `boat_in_times` / `boat_out_times`, never the flag |
| Plan / tier gated | **No** |
| Permission gated | **No** (Stay View additionally requires `view_booking?`, but that is a general booking-visibility rule, not boat-specific) |

### Not plan-gated — for contrast

The audit trail *is* plan-gated:

```ruby
require_feature!("full_audit_trail")   # workspaces_controller.rb:121
```

Boat has no `Feature` record, no `PlanFeature` row, and no `require_feature!`
call anywhere. If boat transfers should ever become a paid or tier-limited
capability, that wiring does not exist yet.

---

## 2. What the switch controls

20 references to the column across `app/`, of which 11 are read sites
(`allow_boat_information?`). Every surface reads that one flag — there is no
second condition layered on top anywhere.

| Surface | Behaviour when off |
|---|---|
| Guest details panel | Boat FieldSet not rendered |
| Check-in sheet | Boat section not rendered |
| Booking creation (new / quick / walk-in / backdated) | Boat section not rendered |
| Front Desk — Bookings / Arrivals / In-House / Departures / Checkout | Column and mobile card band both dropped |
| Stay View — timeline | Popover boat rows dropped |
| Stay View — room cards | `LoadInventory` selects `NULL` for both columns (`load_inventory.rb:247`) |
| Reports — Boat Transfers tab | Tab hidden; direct URL redirects to Arrivals |
| Reports — Meal Prep tab | Same (see §3) |
| Reports — Arrivals / In-House / Departures / Checkout | Boat column dropped from screen **and** CSV export |
| Settings — Daily Boat Schedule | Section hidden |
| Writes | `Boats::ResolveTimes` returns `{}` — forged params ignored server-side |

The Stay View treatment is the strongest: the data never leaves the database,
rather than being hidden in the view.

---

## 3. Meal Prep is correctly coupled

`reports_controller.rb:374` hides **both** `bibo` and `meal_prep` behind the
flag. This initially looks like a miswiring — meal prep is not boat information.

It is correct. `MealPrepReport` derives every row from `boat_in_at` /
`boat_out_at` (`meal_prep_report.rb:27-54`); breakfast/lunch/dinner counts come
purely from what hour the boat lands or leaves. With the flag off there are no
boat times, so the report would always be empty.

**Do not decouple these without first giving Meal Prep a non-boat data source.**

---

## 4. The open decision: opt-out vs opt-in

The default is `true`, so **every hotel in the system has boat transfers enabled
right now** unless someone deliberately turned it off. A city hotel with no
jetty is currently carrying boat columns across five Front Desk tabs, two
report tabs, and three booking forms.

### Option A — stay opt-out (today's behaviour)

Every hotel gets it; admin switches it off per property.

- No migration, no backfill, nothing to ship.
- Correct for a portfolio that is mostly island resorts.
- Cost: irrelevant UI on mainland properties until someone notices and asks.
- Failure mode is cosmetic clutter, which nobody reports as a bug.

### Option B — flip to opt-in

Change the column default to `false`; admin switches it on per property.

- Needs a migration for the default **plus** an explicit decision about existing
  rows. A default change does not touch existing records, so today's hotels stay
  `true` unless backfilled.
- Correct if most properties are mainland and islands are the exception.
- Risk: a backfill to `false` silently hides boat times that staff are already
  relying on. Any backfill should skip hotels with `boat_in_times` /
  `boat_out_times` configured, or with any `booking_guests` row holding a
  non-null `boat_in_at` / `boat_out_at`.

### Option C — make it a plan feature

Add a `Feature` slug and `require_feature!`, matching the audit trail.

- Only worth doing if boat transfers should be monetised or tier-limited.
- Largest change: feature record, plan associations, seed data, and every one of
  the 11 read sites re-pointed at the feature check.
- Would also need a fallback rule for hotels that have data but lose the plan.

**Leaning:** A, unless the property mix says otherwise. The current cost is
cosmetic and reversible; Option B's backfill is the only step here that can
actually destroy visible information.

---

## 5. Secondary consideration — who owns the switch

Hotel staff cannot turn the feature off for their own property; only a platform
admin can. That is defensible (it keeps report tabs and export schemas stable
per property) but it means a mainland hotel that finds the columns irrelevant
has to raise a support request for what is a cosmetic preference.

Worth deciding separately from §4: if the answer to §4 is "stay opt-out", this
question gets more pressing, because opt-out is precisely the mode where
individual hotels end up wanting to switch it off themselves.

---

## 6. If Option B is chosen

Rough shape, not a plan:

1. Migration: `change_column_default :hotels, :allow_boat_information, from: true, to: false`.
2. Decide explicitly whether to backfill existing rows. **Default answer: no.**
   Leave current hotels enabled and let admin switch off the ones that do not
   need it — this makes the change non-destructive.
3. If a backfill is wanted anyway, exclude any hotel that has a configured
   timetable or any booking guest with a stored boat time. **Watch the
   predicate** — `jsonb` does not compare the way the Rails idiom implies:

   ```ruby
   Hotel.where.not(boat_in_times: []).count   # => 17 — matches everything
   ```
   ```sql
   select count(*) from hotels where jsonb_array_length(boat_in_times) > 0   -- => 1
   ```

   Written the obvious way the guard protects nothing. (Moot once §7 lands and
   the timetable is rows rather than jsonb.)
4. Update the admin create form default (`create_form.rb:48` currently coerces
   `nil` to `true`).
5. Update `spec/factories/hotels.rb` expectations — the factory does not set the
   attribute, so it inherits whatever the column default is, and several specs
   rely on boat being available without saying so.

Step 5 is the one most likely to be missed: flipping the default silently
changes the starting state of every spec that does not set the flag explicitly.

---

# 7. Built — boat settings and schedules tables

**Status:** implemented on `boat-transfer-select` · **Added:** 2026-07-29

Moves the timetable out of the two `hotels` jsonb columns and makes the meal
rules per-property instead of hardcoded (`LUNCH_FROM = 12`, `DINNER_FROM = 17`
in `MealPrepReport`).

## 7.1 Decisions locked

| Decision | Choice |
|---|---|
| Custom / off-timetable time entry | **Removed.** Every boat time is a schedule row. |
| Retiring a slot | **Soft delete.** Rows are archived, never destroyed. |
| Hotel with no slots | **Hide the boat section entirely** rather than render an unusable control. |
| Settings location | **Its own "Boat Settings" tab** in the General group, after General. |
| Source of truth for meal eligibility | The **stored per-slot flags**. Meal times only pre-fill them. |

## 7.2 Schema

```ruby
create_table :hotel_boat_settings do |t|
  t.references :hotel, null: false, foreign_key: true, index: { unique: true }
  t.time :breakfast_time
  t.time :lunch_time
  t.time :dinner_time
  t.timestamps
end

create_table :hotel_boat_schedules do |t|
  t.references :hotel, null: false, foreign_key: true
  t.time     :time, null: false
  t.string   :kind, null: false                  # boat_in | boat_out
  t.boolean  :has_breakfast, null: false, default: false
  t.boolean  :has_lunch,     null: false, default: false
  t.boolean  :has_dinner,    null: false, default: false
  t.datetime :archived_at                        # soft delete
  t.timestamps
  t.index [ :hotel_id, :kind, :time ], unique: true
  t.index [ :hotel_id, :kind, :archived_at ]
end
```

Notes on the shape:

- `hotel_boat_settings` follows the existing `has_one` satellite precedent
  (`Hotel has_one :hotel_transaction_configuration`). `hotels` is already 46
  columns; these do not belong on it.
- `kind` uses `boat_in` / `boat_out`, **not** `arrival` / `departure` — the
  latter already mean check-in/check-out in the Front Desk tabs, and the rest of
  the codebase says boat_in/boat_out throughout.
- Unique index replaces the `.uniq` that `Boats::Schedule#normalize` does in
  Ruby today.
- `time` is a Postgres `time` (no zone): a daily timetable slot is a time of
  day. The calendar day is attached at booking time by
  `Boats::Schedule.timestamp`, which stays as is.

## 7.3 Why soft delete is required, not preferred

A hotel drops its 09:30 slot. Guests already booked on it still hold a
`booking_guests.boat_in_at` of 09:30. With a hard delete there is no row to read
`has_lunch` from, and those guests silently vanish from Meal Prep — changing
counts for periods that have already been cooked and reconciled.

Archiving means:

- the dropdown lists only `archived_at IS NULL` rows;
- the meal lookup resolves against **all** rows, archived included;
- past reports stay reproducible.

It also replaces the "inject the stored off-schedule value as an extra option"
logic in `Boats::Schedule#choices` — the archived row *is* that option, so that
branch can go.

## 7.4 Meal eligibility

One rule, one place:

```
booking_guests.boat_in_at → time of day (hotel zone) → matching schedule row → has_*
```

No fallback and no derivation at read time, because there is no longer any way
to record a boat time that has no row.

`hotel_boat_settings.{breakfast,lunch,dinner}_time` has exactly one job: when
staff add a slot, pre-tick the three checkboxes. It never feeds the report. Keep
that boundary explicit or the two tables will drift and nobody will know which
one the kitchen is reading.

## 7.5 Settings tab wiring

Concrete touch points for the new tab (all currently exist and are small):

| File | Change |
|---|---|
| `config/routes.rb` (~:546) | `get/patch "general/boat"`, `defaults: { settings_page: "boat" }` |
| `settings_controller.rb:5` | add `"boat"` to `SETTINGS_PAGES` |
| `settings_controller.rb#settings_page_path` | add the `"boat"` branch |
| `settings_controller.rb#settings_page_for_form` | map `form_id` `"boat_settings"` → `"boat"` |
| `settings_navigation_helper.rb:102-108` | insert the tab into the `:general` group, after General |
| `settings/index.html.erb:7` | add the `when "boat"` render branch |
| `settings/_boat_section.html.erb` | **new** — slots table + meal times |
| `settings/_general_section.html.erb:153-204` | **delete** the Daily Boat Schedule block |

Permission stays `manage_hotel_profile`, matching the other General tabs.

## 7.6 What gets deleted

The custom-time escape hatch, across 9 files:

- `Boats::Schedule` — `CUSTOM_VALUE`, `CUSTOM_LABEL`
- `Boats::ResolveTimes` — the custom branch and `boat_*_custom_time` params
- `app/javascript/controllers/boat_time_field_controller.js` — whole file
- `bookings/_boat_transfer_field.html.erb` — the revealed picker
- `check_ins_controller.rb`, `booking_creation_base_controller.rb` — param permits
- 3 spec files — the custom-time cases

Plus `app/javascript/controllers/boat_schedules_controller.js`, whose
add/remove-row job the new tab supersedes.

## 7.7 Migration and backfill

1. Create both tables. Keep the jsonb columns for one release (same two-release
   contract used for the invoice table consolidation).
2. Backfill `hotel_boat_schedules` from **every distinct boat time already in
   use**, not just the current timetable — union of `hotels.boat_in_times` and
   the distinct time-of-day of `booking_guests.boat_in_at` (same for out).
   Skipping the second half orphans the seeded year of history on day one.
3. Set `has_*` from **today's hardcoded rules**, not from the new meal times, so
   the switch changes no existing number:

   | Boat-in | Today's rule | Derived from meal times (08:00 / 12:00 / 19:00) |
   |---|---|---|
   | 09:30 | Breakfast, Lunch, Dinner | Lunch, Dinner |

   Hotels then adjust their own slots deliberately, and any change in the
   numbers is one they made.
4. Seed default slots for hotels with `allow_boat_information` on but no
   timetable — **16 of 17 hotels today** (see §4). Without this they get a boat
   section that §7.1 will hide, i.e. the feature silently disappears for them.
5. Point `Boats::Schedule#in_times` / `#out_times` at the tables. This is the
   seam: the booking forms, check-in, Front Desk columns and Stay View all go
   through it and should need no changes.
6. Drop `hotels.boat_in_times` / `boat_out_times`. **Done** —
   `DropBoatTimesFromHotels`, taken in the same release rather than the next one
   by explicit decision. `hotel_boat_schedules` is now the only timetable.

   The rollback re-adds the columns and rebuilds them from the live slot rows,
   so reverting lands on usable data. It cannot restore the *original* arrays:
   the backfill read from them, so after this migration they are gone and the
   backfill cannot be re-run.

## 7.9 Built — notes from the implementation

- Postgres `time` columns are **zone-aware in Rails**: an 08:00 slot written in
  one zone reads back as 22:00 in another. Both models set
  `self.time_zone_aware_types = [ :datetime ]` so a slot stays the wall-clock
  label it is. Covered by a spec that round-trips through three zones.
- The retire/restore route is `hotel_boat_schedule_slot_restore_path`; the
  surrounding scope supplies the `hotel_` prefix.
- `Boats::Schedule#enabled?` counts **active** slots only — a property whose
  slots are all retired hides the boat section, same as one that never had any.
- §6's jsonb-predicate warning is now moot: the columns no longer exist.

## 7.8 Residual risks

- **Retroactive edits.** Changing a slot's `has_lunch` changes past reports.
  Today's rules live in code so this is not a regression, but it becomes an
  end-user action rather than a deploy. If reports are ever reconciled against,
  the flags want versioning or a snapshot onto `booking_guests`.
- **Step 4 is easy to skip** and its failure is silent: the feature just stops
  appearing for most properties.
- **Two tables, one question.** If `has_*` and the meal times are ever both
  treated as authoritative, meal counts become unexplainable. §7.4 is the rule.
