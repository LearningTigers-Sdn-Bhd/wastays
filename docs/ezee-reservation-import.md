# Importing future reservations from eZee

**Status: planned, not built.** Every decision below is settled with the client.
This document is the working context for the feature: what the file is, what
wastays requires, what was decided and why, and which questions are still open.
Read it before touching the importer — several of the constraints here are not
discoverable from the code alone.

The goal: a property arriving from eZee already has a book of **future**
reservations. Those must exist in wastays on day one, or the front desk runs two
systems through the changeover. Past bookings are out of scope — see 2.0.

---

## 1. The source file

Sample: `~/Downloads/ Reservation List_20250422.xls` (note the leading space in
the filename). Exported 22 Apr 2025 by KINABALU PINE RESORTS SDN BHD, covering
arrivals 01–31 May 2025.

**This sample is historical data.** It is what the client happened to send, not
what the feature is for — every arrival in it is long past. It remains the
reference for *layout and data habits*, which is what §1 documents. For anything
that actually runs the importer, use the future-dated fixture in §7.

It is a **real BIFF `.xls`** — an OLE2 compound document, not the
HTML-in-a-.xls-suffix that many PMS exports turn out to be. `file(1)` reports
`Composite Document File V2`. It is Crystal Reports output: a banner block, then
a 48-column grid of merged cells, then summary blocks.

### Layout

- Sheet 1, `Sheet1`, 4149 rows × 48 columns.
- Rows 0–8: banner (property name, print date, the filter that was applied).
- Row 9: header labels, themselves spread across merged cells.
- Row 13: group header `Active Reservation`.
- Rows 14–4120: data.
- Rows 4121+: `Group Total`, `Summary Report`, `Grand Total` blocks. Skip.

**69% of the file's rows are completely blank.** Crystal Reports pads every
record: data rows sit 4 apart normally and 5 apart after a remark, and the
longest run of consecutive blank rows is 4. This breaks three common parsing
idioms, so the contract has to be stated explicitly:

- **Never "read until the first blank row."** On this file that yields 1 data
  row out of 1193, without raising.
- **Never stop after N consecutive blanks.** The longest legitimate run is 4, so
  any threshold of 4 or less truncates the import mid-file.
- **Never advance by a fixed stride.** The stride is 4, except after a remark
  row where it is 5.

The rule that survives all three: **iterate to the last row, classify each row by
its content, and never terminate on emptiness.**

Cell values themselves are clean — no data cell in the sample carries leading or
trailing whitespace — with two exceptions worth knowing: one agency name has an
internal double space, and **one remark cell begins with a newline**
(`"\ncancle"`), so remark text is not guaranteed to be a single line.

Columns are **fixed offsets**, because the header text cannot be read reliably
from merged cells:

| Col | Field | Example |
| --- | --- | --- |
| 2 | Rsrv. No | `291016` |
| 5 | Rsrv. Date | `12-Apr-23 16:45:01` |
| 10 | Source | `Travel Agent -` |
| 16 | Guest Name | `HAPPY TRAILS BORNEO TOURS SDN BHD` |
| 23 | Arrival | `02-May-25 14:00:00` |
| 26 | Departure | `03-May-25` |
| 28 / 31 | Adults / Children | `2` / `0` |
| 33 | Nights | `1` |
| 35 | Room No | `E3` |
| 37 | Room Type | `STD` |
| 38 | Rate Type | `Agent` |
| 40 | Total Amt. | `210.00` |
| 42 | Amt. Paid | `0.00` |
| 46 | User | `Emily` |

Column 30 is a literal `/` separator between adults and children on every row.

### Row kinds

A row with **only column 2 populated** is one of two things:

- a **group header** (`Active Reservation`) — appears before any data row in its
  block;
- a **Reason / remarks** line belonging to the reservation **above** it.

In the sample the remarks are: `cancel`, `CXL`, `cxl`, `cancle`, `CANCEL`,
`IPAY88`, `IPAY88- FIXED N1 P1 P2 FAMILY`, `NONSMOKE, TWINBEDS`,
`LARGE BED, NON SMOKE`, `SIDE BY SIDE`, `PASTIKAN SAMA BILIK SAMA NEXT DAY DIA`,
`FIXED TINGKAT ATAS. COD: 17.04.2025`, `NONSMOKE, LARGEBED, QUIETROOM, ETA 2PM-3PM.`

Note that several remarks say `cancel` on rows sitting **under the
`Active Reservation` heading**. Staff use the remarks field as a scratchpad;
these are not a status. Do not infer cancellation from remark text.

### Verification anchor

The file states its own `Group Total : 1193`, and exactly **1193 rows** parse as
data. The importer should assert parsed-row-count against that total and refuse
the file on mismatch — it is the cheapest possible guard against a layout change.

### Facts established by profiling the sample

**1193 rows. One row = one room = one reservation number.** All 1193 Rsrv Nos
are unique. A thirteen-room agent block is thirteen rows with thirteen numbers
and no column linking them.

This fits wastays exactly: `booking_rooms` has a unique index on `booking_id`
(`idx_booking_rooms_unique_booking`), so one booking is already one room, and a
multi-room stay is expressed through `group_booking_id` / `group_position`.

**"Guest Name" is polymorphic — what it holds depends on the source.** 156
distinct values over 1193 rows. This is not a broken export; it is how the
property operates the field, and the importer must branch on it:

| Source | Rows | What the name field holds |
| --- | --- | --- |
| `Travel Agent -` | 885 | **Agency name**, always |
| `OTA (KPR ONLINE) -` | 104 | 15 real guest names, **89 blank** |
| `AGODA -` | 84 | 19 real guest names, **65 blank** |
| `Phone Reservation -` | 82 | Real guest names (54 distinct) |
| `Corporate -` | 14 | **Mixed** — see below |
| `TIKET.COM -` | 14 | **All blank** |
| `Internet Reservation -` | 8 | Real guest names (7 distinct) |
| `Walk In -` | 1 | Real guest name |
| `Over-The-Counter -` | 1 | Real guest name |

Trailing ` -` is part of the printed value and must be stripped.

So roughly **140 rows already carry a real person's name**
(`AARON DENNIS DASAN`, `DR JULIET MATTHEW`, `OOI JIA JIN`), **885 carry an
agency name**, and **168 are blank**. Where the field is blank eZee prints the
source instead, so those rows read literally `- KPR ONLINE`, `- AGODA`,
`- TIKET.COM`. One AGODA row reads just `AGODA`.

`Corporate -` is the messy one: 6 distinct values mixing a company
(`BANK NEGARA MALAYSIA`) with company-plus-traveller composites
(`(INA/NURAZRIENA) TOURMIND`, `[MATJIN/SURAYAH]TOURMIND CORP LIMITED`,
`DASAN/ARIEL TOURMIND CORP LIMITED`). These want an operator's eye, not a
parsing rule.

**Blank and agency are different problems.** A blank OTA row means a real guest
name exists in eZee but *this report does not print it* — a different eZee
report would recover it. An agency row means there is **no guest yet**: an agent
has blocked rooms and the rooming list arrives closer to arrival. No export can
supply a name that does not exist.

There is no phone, email, nationality or document number anywhere in this file
for any row. **This report is a reservation list, not a guest list** — those
details live in other eZee reports.

**Room No → Room Type is 1:1 with zero exceptions.** 64 distinct rooms, not one
under two different types. The file therefore doubles as an inventory checklist.

**Room types** — 6: `DLX` (520), `STD` (420), `SP STD` (114), `SDLX S` (85),
`SDLX N` (31), `STD VALLEY` (23).

**Rate types** — 10: `Agent` (876), `Promo` (183), `Agoda` (84), `Corp` (16),
`TIKET` (14), `Pub` (8), `Comp` (4), `Room` (4), and two more in the tail.

**Occupancy** — adults are 1, 2 or 3 (1181 rows are 2). Children is `0` on every
single row. Do not assume that holds for a future export.

**Nights** — 1 (1060), 2 (85), 3 (42), 4 (6).

**Amounts** — `Total Amt.` is the stay total, not per night: it scales linearly
with nights and divides into round per-night figures (`210.00`, `290.00`,
`305.00`, `225.00`). The only non-round values (`190.01`, `419.99`, `629.99`)
are discount rounding artefacts, not a tax residue. **9 rows have
`Total Amt. = 0.00`**, all travel agent. `Amt. Paid` is `0.00` on 1006 rows and
non-zero on 187.

**Users** — 8 eZee operator names (`Aimi` 481, `Emily` 272, …).

**Only one status group** (`Active Reservation`) — this export was pre-filtered.
Do not assume the next one is. Read the group header; refuse anything under a
heading not explicitly handled.

---

## 2. Decisions

All confirmed with the client. Numbering matches the order they were asked.

### 2.0 Scope: future arrivals only

**The feature exists to carry forward a property's unarrived reservations.**
Historical bookings are not the point and are not migrated — the old PMS remains
the record of what already happened.

In **production this is enforced**: a row whose arrival falls before the hotel's
current business date is refused. Use the hotel's business date, not
`Time.current` — a property mid-night-audit has a business date that is not
today, and the arrivals list is driven by the business date everywhere else in
wastays.

Past-dated rows are **reported as skipped with a count and a reason**, never
dropped silently. An operator who exported the wrong date range must be able to
see that is what happened.

**Development uses a future-dated fixture instead of an override.** The only
real file we have is the April 2025 sample, whose arrivals are all long past —
under the production rule every one of its 1193 rows is refused, so it cannot
exercise the importer at all. Rather than build a past-date bypass that would
exist only for tests, **§7 describes a generated fixture with future arrivals**.
The importer therefore needs no environment-gated escape hatch, and the
production rule can be unconditional.

This matters beyond convenience: a bypass flag is a thing that can be switched on
in production by accident. Not having one is the stronger design.

Past-dated rows would also trip `NightAudits::OperationalChangeGuard` and the
availability checks inside `CreateManualBooking`. wastays does have an explicit
backdating concept — `Bookings::CreateStaffBooking` accepts
`booking_type: "backdated_check_in"` with a `backdate_reason` and
`financial_posting_options: { override_night_audit: true }` — but the importer
should not need it.

**Explicit non-goal: guests in-house at cutover.** A property switching systems
mid-week has guests who arrived under eZee and depart under wastays. Those are
neither past nor future, and this importer does not handle them. That is a
deliberate exclusion, not an oversight — but it is a real situation at go-live
and needs its own decision before then.

### 2.1 Build for this file, and take the name field as it stands

Build the importer for the sample described above — the file actually in hand.
Design the parser so a guest-bearing eZee report can slot in later as an
additional mapping, without a rewrite.

**Store `guest_name` exactly as the file gives it**, including the agency name
on travel-agent rows. That is how Kinabalu Pine Resorts uses the field, and the
importer should not second-guess a property's own record-keeping. The agency is
*additionally* attached as a corporate account (2.6), so nothing is lost by the
name also naming the agency — the relationship is captured structurally either
way.

Handle the three cases by source (see §1):

- **Real person name** (~140 rows) — import as `guest_name`. Nothing further.
- **Agency name** (885 rows) — import as `guest_name`, and attach the corporate
  account. There is **no missing data here**: an agent has blocked rooms and the
  guest genuinely is not known yet. The rooming list arrives closer to arrival.
- **Blank** (168 rows, printed as `- AGODA` etc.) — do **not** store the
  `- SOURCE` placeholder as a name. These rows have a real name in eZee that
  this report does not print.

That last case is the only genuinely incomplete one, and it is 168 rows rather
than the whole file. Flagging it is cheap and worth doing; a heavyweight
"incomplete import" concept across all 1193 bookings is not warranted.

`bookings.guest_phone` is `null: false` with a presence validation
(`app/models/booking.rb:360`) and no row in this file has a phone. Relaxing that
validation would weaken every other creation path, so the importer writes a
sentinel the portal renders as "not captured" rather than a fake number a staff
member might dial.

**The agency name is permanent, not a placeholder awaiting a rooming list.**
This is established by the file itself, and it is the single most important
thing to understand about the guest-name field.

A reservation list prints the *current* value of each record at export time, not
what was typed at booking. This file was printed **22 Apr 2025** and covers
**May 2025 arrivals**, some of them 1–10 May — barely a week out, by which point
a rooming list for an agent block would have arrived. Every one of those rows
still names the agency. Of 61 distinct travel-agent values, **59 are company
names**; only `MS LOW SIOW ENG` and `MUHAMMAD HAFIZ BIN ZAKARIA` are person
names, and those read as sole traders rather than renamed records.

Reservation dates in the file run from **Jan 2022** through 2025, so these
records have had years to be renamed and were not. The property does not
overwrite the agency name with the traveller's name — ever.

Two consequences:

- Do **not** build anything that treats the agency name as a temporary value to
  be replaced later. There is no rename event to wait for.
- The traveller's name for an agent block is captured at check-in, through the
  registration card, against the `booking_guests` records — not by editing
  `guest_name`. That is also how wastays already models it.

**Settled: the agency name is accepted, and the hotel renames later.** The
client has confirmed that storing the agent name as `guest_name` is fine for
imported future bookings, because they will update it to the traveller's name
once that is known.

Note the tension with the evidence above, and design for it: in eZee the
property never renamed a record, across reservations up to three years old. The
stated intent for wastays is different. Both are fine as long as **nothing
depends on the rename happening** — do not put imported bookings into a blocking
or "incomplete" state that only a rename clears, and do not build a report whose
correctness assumes `guest_name` is a person.

This costs nothing to honour, because `guest_name` is an ordinary editable field
and `booking_guests` already carries the real guest identity captured at
check-in. If the rename habit takes, the field improves on its own. If it does
not, every imported booking still works exactly as it does on day one.

### 2.2 Pricing: take the eZee amount as-is, exclude tourism tax

Malaysian tourism tax applies **only to foreign guests**, and this file carries
no nationality. So it cannot be computed, and the client's instruction is to
**exclude it** and keep the amount exactly as eZee states it.

**Excluding it is free.** `Hotel#tourism_tax_applicable_for?`
(`app/models/hotel.rb:579`) returns `false` when `country.blank?`:

```ruby
def tourism_tax_applicable_for?(country)
  return false unless tourism_tax_enabled?
  return false if country.blank?

  !country.casecmp("Malaysia").zero?
end
```

So leaving `guest_country` blank on imported bookings yields
`tourism_tax_amount == 0` through `BuildFinancialSnapshot`, with no special
casing. This is also the honest representation: we genuinely do not know the
nationality. **Do not write a placeholder country** — `"Malaysia"` would be a
guess that silently suppresses tax for real foreigners, and anything else would
wrongly charge it.

**"Keep the amount as-is" means `booking.total_amount` must equal `Total Amt.`
exactly.** This is the trap in the feature:

`manual_rate_override` is **tax-exclusive**. It is the *room* total, and
`BuildFinancialSnapshot` applies the hotel's room-revenue tax rules on top of
it. Passing `210.00` straight through produces a booking totalling `226.80` if
SST is configured — not as-is.

`Bookings::SolveRoomTotalForFinalAmount`
(`app/services/bookings/solve_room_total_for_final_amount.rb`) exists for
precisely this: give it a target final total and it back-solves, by fixed-point
iteration, the room total that produces it. **Use it, with
`target_total = Total Amt.` and `guest_country = nil`.** The booking then totals
exactly the eZee figure, SST is represented coherently inside it, and tourism
tax is absent.

If the new hotel (see 2.5) is configured with no room-revenue tax rules at all,
both paths coincide and this distinction is moot — but the importer should not
depend on that.

**The 9 zero-amount rows need a rule rather than a crash.** `CreateManualBooking`
rejects a zero total when recording payment, and `SolveRoomTotalForFinalAmount`
has explicit handling for a zero target. Decide: import at zero as
complimentary, or stage them as needing review.

### 2.3 `Amt. Paid` becomes a pre-migration opening balance

187 rows carry money already taken in eZee. Importing those as wastays payment
transactions would misstate the new system's revenue — the money never moved
through wastays.

Record them as an **opening deposit balance on the folio, flagged
pre-migration**, so the arrival balance is correct without inventing a
transaction that never happened. The client has agreed in principle; the exact
posting should be confirmed with whoever owns the books before go-live.

### 2.4 Accept multiple file formats

The importer must be **flexible about format** — `.xls` (BIFF), `.xlsx`, and
CSV. Do not build a parser that only reads the sample.

Implication: `roo` + `roo-xls` (which pulls in `spreadsheet`) are needed for the
BIFF path. `csv` is already in the Gemfile; `caxlsx` is write-only and no use
here. Structure the reader as a format-detecting front end producing a uniform
row stream, with the eZee column mapping applied on top — so a differently
shaped export becomes a new mapping, not a new importer.

Header cleaning is explicitly permitted. The client does not require the file to
be passed through untouched.

### 2.5 A new hotel will be created to match the room and rate types

The property does not exist in wastays yet — the dev database holds only seed
hotels. The client will **create a new hotel and set up its room types and rate
types to match the file**.

The file is the checklist: 64 rooms, 6 room types, 10 rate types, all listed in
§1. Nothing imports until these exist, because `CreateManualBooking` validates
room availability through `AvailableRoomNumbers`.

Room number → room type being 1:1 in the file means the inventory can be
generated from the file itself and checked against what was set up.

### 2.6 Travel agencies become corporate accounts

885 rows name a real agency. Match or create `hotel_corporate_accounts`.

**Two records are needed per agency**: a global `CorporateAccount` and a
`HotelCorporateAccount` joining it to this hotel, because
`hotel_corporate_accounts.corporate_account_id` is `null: false`. Also note
`credit_currency` is `null: false`, and `agent_code` is unique per hotel.

Around 150 agencies will come out of the file. Created accounts get
`direct_bill_enabled: false`, no credit limit and no payment terms — inventing
credit terms for a property is not the importer's business.

Matching is on **normalised name**, and the sample shows exactly why the review
screen earns its place. The 61 raw travel-agent values contain:

- **A double space** — `AMAZING BORNEO TOURS & EVENTS  SDN BHD` alongside
  `AMAZING BORNEO TOURS & EVENTS SDN BHD`. Whitespace collapse catches it.
- **A typo** — `INTERPID TRAVEL (MALAYSIA) SDN BHD` alongside
  `INTREPID TRAVEL (MALAYSIA) SDN BHD`. No normalisation rule catches this; a
  human has to merge them.
- **Punctuation variance** — `BAHTERA KEMBARA HOLIDAYS SDN.BHD.` against the
  usual `SDN BHD`.
- **A name typed twice into one field** —
  `BORNEO BIRDING TOURS SDN BHD BORNEO BIRDING TOURS SDN BHD`.
- **Status prefixes typed into the name** —
  `POSTPONE AMAZING BORNEO TOURS & EVENTS SDN BHD` and
  `POSTPONED-BORNEO HOLIDAY AND VEHICLES RENTAL SDN BHD`. Staff mark state by
  editing the name field, the same scratchpad habit that puts `cancel` in the
  remarks (§1). **Strip these prefixes before matching**, or two accounts get
  created for one agency and the postponed bookings detach from its ledger.
- **Possible relations that are not obviously the same** —
  `HAPPY TRAILS BORNEO TOURS SDN BHD` and `HAPPY TRAILS MALAYSIA TOURS`. Only
  the client can say whether that is one agency or two.
- **Two person names** — `MS LOW SIOW ENG`, `MUHAMMAD HAFIZ BIN ZAKARIA`, filed
  under Travel Agent. Probably sole traders; they still need an account or an
  explicit decision not to have one.

So ~61 raw values collapse to roughly 56 real agencies, and the last few
collapses cannot be automated. The review screen must let an operator point two
spellings at one account before the import commits.

### 2.7 Multi-room groups are inferred, then reviewed

1078 of 1193 rows sit in a multi-room block; 115 are genuine singles.

**Inference rule: agency + arrival + departure.** Contiguous reservation numbers
and near-identical booking timestamps are *confirming signals, not the rule* —
the sample contains a 13-room block whose numbers skip (`305558`, `305559`,
`305561`) because the missing ones were cancelled, so contiguity alone would
split blocks that belong together. Observed evidence: `291016`…`291023` booked
`12-Apr-23 16:45:01` through `:04`; `308101`…`308111` booked within 5 seconds.

Group size distribution in the sample: 115 singles, 58 pairs, 24 triples, and a
long tail up to two blocks of 24 rooms.

**Staff review the proposed groups before commit**, because the inference is a
guess about intent: two separate bookings from the same agent for the same night
are indistinguishable from one two-room block. Staff can split or merge. This is
the whole justification for a two-phase import.

Commit path: `GroupBookings::CreateFromBookings`, exactly as
`Bookings::CreateStaffBooking` already does.

---

## 3. How a row becomes a booking

**Reuse `Bookings::CreateManualBooking` per row.**
(`app/services/bookings/create_manual_booking.rb`) It is already the one-room
creation path — it builds the `booking_room`, the financial snapshot and the
folio. Going around it means reimplementing all of that.

`Bookings::CreateStaffBooking` is the reference for orchestrating many rows plus
grouping; read it before writing the importer's commit step.

### Field mapping

| eZee | wastays |
| --- | --- |
| Rsrv. No | `external_reference` |
| Rsrv. Date | `created_at` (see gaps) |
| Source | `source`, via `BookingSource` |
| Guest Name | `guest_name` as-is; agency rows also → `hotel_corporate_account_id`; blank rows flagged, not stored |
| Arrival / Departure | `check_in` / `check_out` |
| Adults / Children | `adults` / `children` |
| Room No | `booking_rooms.room_number` |
| Room Type | `booking_rooms.room_type_id` |
| Rate Type | `booking_rooms.rate_plan_id` |
| Total Amt. | target total via `SolveRoomTotalForFinalAmount` |
| Amt. Paid | pre-migration opening deposit balance |
| Reason row | `special_requests` |
| User | `internal_notes` |
| — | `guest_country` stays **blank** (see 2.2) |
| — | `guest_phone` sentinel (see 2.1) |

### The eZee reservation number does not become the wastays one

`Booking` allocates its own through `DocumentIdentifiers::Issuer`
(`app/models/booking.rb:804-817`), and those numbers feed invoices and
tourism-tax vouchers. The eZee number goes in `external_reference`, which is
indexed (`index_bookings_on_external_reference`), so the desk can still find a
reservation by the number an agent quotes over the phone.

**The import UI and the portal search must both look up `external_reference`.**

### Source mapping

Mostly clean against `BookingSource::DEFAULT_SOURCES`
(`app/models/booking_source.rb:26`):

| eZee | wastays key |
| --- | --- |
| `Phone Reservation -` | `phone` |
| `Walk In -` | `walk_in` |
| `Over-The-Counter -` | `walk_in` |
| `AGODA -` | `agoda` |
| `Internet Reservation -` | `direct` |
| `Corporate -` | `internal` + corporate account |
| `Travel Agent -` | `internal` + corporate account |
| `OTA (KPR ONLINE) -` | `direct` — the property's own booking engine, despite the label |
| `TIKET.COM -` | **no key exists — must be added to the registry** |

`BookingSource` also has a `SOURCE_ALIASES` map for channel spellings; the eZee
spellings belong there rather than in the importer.

### Booking attributes that are NOT NULL

From `db/schema.rb`, the ones the importer must satisfy: `adults`, `check_in`,
`check_out`, `confirmation_token` (auto), `currency` (defaults `MYR`),
`guest_name`, `guest_phone`, `hotel_id`, `reservation_number` (auto),
`reservation_year` (auto), `status`, `total_amount`, `fund_collector`.

`guest_email` is validated present **unless `created_by_staff?`**
(`app/models/booking.rb:364`). `CreateManualBooking` sets
`created_by_staff = true`, so the importer gets that exemption for free — but
only through that service.

---

## 4. Two phases

**Phase 1 — Stage.** Upload, parse, resolve everything, save the result, change
nothing. Produces: every parsed row with its proposed mapping; unresolved
room-type and rate-plan mappings; agencies that would be created; proposed
groups; every row that would fail and why.

**Phase 2 — Commit.** Operator has fixed mappings and adjusted groups; the
import runs in a background job and creates the bookings.

The split is not politeness. `CreateManualBooking` validates availability
through `AvailableRoomNumbers`, so a row can fail on inventory that has not been
set up yet — and discovering that 900 bookings in is useless. Staging surfaces
every such failure before anything is written.

Staging also makes the import **re-runnable**, which it must be: the client will
export again closer to cutover. Rows are identified by `external_reference`
scoped to the hotel, so a second run updates what changed, skips what did not,
and reports what disappeared (cancelled in eZee since the last export). A first
import that cannot be re-run is a first import that has to be deleted by hand.

Run the parse in a background job regardless: 1193 rows through
`CreateManualBooking`, each building a financial snapshot and a folio, is not a
request. Solid Queue is the project's job backend.

### Where it lives

`Admin::` — the existing back-office namespace
(`app/controllers/admin`). This is a migration tool run once per property by
whoever is onboarding it, not a feature a hotel uses. It does not belong in the
hotel portal. There is no `Superadmin::` namespace in this codebase.

---

## 5. Known gaps — decide, do not discover

**Tourism tax is never recovered after check-in.** This is the most important
one. Imported bookings carry a blank `guest_country`, so tourism tax is zero. At
check-in the registration card captures nationality — but
`Bookings::ProcessCheckIn` only records `tourism_tax_collected`
(`app/services/bookings/process_check_in.rb:204`); it does **not** recompute the
tax from a newly-known country. `Bookings::UpdateStayService` *does* rebuild the
snapshot with `guest_country` and recompute
(`app/services/bookings/update_stay_service.rb:83,107-108`), so the recovery
path exists — but only if someone re-saves the stay.

Left alone, **the property will under-collect tourism tax on every imported
foreign guest.** Either wire the recomputation into check-in for imported
bookings, or give the desk an explicit prompt. Do not ship without choosing.

**The 168 blank-name rows want a second eZee report.** Unlike the agency rows,
these have a real name that simply is not printed on a reservation list. Worth
asking the client for the report that carries it before go-live, since it is a
one-off fetch rather than a code change.

**Cancelled and no-show rows.** Absent from the sample because it was filtered.
If a future export includes them, they either import with the right status or
are refused loudly — never skipped silently. Remember that remark text saying
`cancel` is *not* a status (§1).

**Rate Type → rate plan mapping** is per-property and must be operator-
configured, not a constant in code. Ten values in this file alone.

**Room assignment.** eZee pre-assigns a room to every future reservation.
Importing the assignment preserves the desk's plan, but means the import fails
on any room already held in wastays. Recommended: import the assignment, and
fall back to unassigned with a warning rather than failing the row.

**`Rsrv. Date` → `created_at` is a lie of convenience.** The booking was created
by the importer today, not in 2023. It matters because reports group on it. If
any report should show when the agent actually booked, that needs a dedicated
column.

**`NightAudits::OperationalChangeGuard`** is called at the top of
`CreateManualBooking#call` and can refuse creation depending on night-audit
state. A large import will hit it. Decide how the importer handles that.

---

## 6. Reproducing the analysis

The profiling in §1 was done with Python + `xlrd` 2.x (which reads `.xls` only;
`.xlsx` support was dropped in 2.0). No project tooling reads BIFF today.

```bash
python3 -m venv xlsenv && ./xlsenv/bin/pip install xlrd
./xlsenv/bin/python -c '
import xlrd, re
b = xlrd.open_workbook("/path/to/ Reservation List_20250422.xls")
s = b.sheet_by_index(0)
v = lambda r, c: str(s.cell_value(r, c)).strip()
rows = [r for r in range(12, s.nrows) if re.fullmatch(r"\d{4,}", v(r, 2)) and v(r, 23)]
print(len(rows), "data rows")
'
```

That row predicate — column 2 is a 4+ digit number **and** column 23 is
non-empty — is what cleanly separates data rows from group headers, remark
lines and the summary blocks. It yields exactly 1193 on the sample.

---

## 7. The test fixture

`spec/fixtures/files/ezee_reservation_list_sample.xls` — **70 reservations
arriving 02–30 Oct 2026**, in the identical eZee format. This is what specs and
manual testing run against; the client's real file is reference material only
(§1).

Generated by `spec/fixtures/files/ezee_reservation_list_generator.py`, which is
committed alongside it. Regenerate when the dates go stale:

```bash
pip install xlwt          # writes BIFF .xls; xlrd 2.x reads it
python3 spec/fixtures/files/ezee_reservation_list_generator.py
```

The generator is seeded (`random.seed(20260914)`), so regenerating without
editing it reproduces the file byte-for-byte in content. The anchors to bump are
`PRINTED_ON`, `ARRIVAL_FROM` and `ARRIVAL_TO` at the top.

### What it reproduces faithfully

- BIFF `.xls`, `Sheet1`, 48 columns, the Crystal Reports banner, header labels
  on row 9 at their real offsets, `Active Reservation` on row 13, data from row
  14 with the same 4-row stride and 5-row stride after a remark.
- The full `Group Total` / `Grand Total` / `Summary Report` / per-source footer,
  at the exact column offsets the real file uses.
- The property's real 64-room inventory and its room → type mapping, so
  room-number-implies-room-type still holds with zero exceptions.
- All 9 sources in roughly the real proportions: Travel Agent 51, OTA (KPR
  ONLINE) 5, Phone Reservation 4, AGODA 3, Corporate 2, and one each of
  Internet Reservation, Walk In, Over-The-Counter, TIKET.COM.
- Reservation numbers ascending **with gaps**, so group inference cannot rely on
  contiguity (§2.7). Group sizes: 26 singles, 4 pairs, 2 triples, 3 fours, a
  five and two sixes.
- Remark rows on their own row carrying only column 2 — 7 of them, including a
  `cancel` sitting under the `Active Reservation` heading, which is the trap
  described in §1, and one whose text begins with a newline.

### Deliberate edge cases

Each of these exists to break a naive parser. Keep them when regenerating.

| Case | Where |
| --- | --- |
| Zero amount | resv `412362`, a `Comp` rate |
| Non-round amount (discount residue) | resv `412361`, `190.01` |
| Three adults | one `SP STD` row |
| Single occupancy | two rows, `adults = 1` |
| Blank guest name printed as `- SOURCE` | 6 rows: `- KPR ONLINE`, `- AGODA`, `- TIKET.COM` |
| Agency name with a double space | `AMAZING BORNEO TOURS & EVENTS  SDN BHD` |
| Agency name typo | `INTERPID` vs `INTREPID TRAVEL (MALAYSIA) SDN BHD` |
| Agency punctuation variance | `BAHTERA KEMBARA HOLIDAYS SDN.BHD.` |
| Agency name typed twice | `BORNEO BIRDING TOURS SDN BHD BORNEO BIRDING TOURS SDN BHD` |
| Status prefix in the name | `POSTPONE …`, `POSTPONED-…` |
| Person filed as a travel agent | `MS LOW SIOW ENG` |
| Ambiguous relation | `HAPPY TRAILS BORNEO TOURS SDN BHD` vs `HAPPY TRAILS MALAYSIA TOURS` |
| Corporate name as a composite | `[MATJIN/SURAYAH]TOURMIND CORP LIMITED` |
| Remark text with a leading newline | `"\ncancle"` — copied from the real file |
| Multi-night stays | 2, 3 and 4-night stays |

18 distinct travel-agent name values, which collapse to roughly 14 real
agencies — enough to exercise the matching and merge review of §2.6.

**One deliberate deviation from the real file:** one row carries
`children = 1`. Every row in the client's export has `children = 0`, which is
exactly the kind of accident a parser hardcodes. The fixture makes sure it
cannot.

### Invariants the fixture guarantees

These are worth asserting in a spec, because they are what make the file
importable rather than merely parseable:

- **70 data rows**, matching the file's own `Group Total : 70` — the §1
  verification anchor works here too.
- **No room is double-booked.** The generator tracks occupancy per room and
  never overlaps two stays, so every row can pass the `AvailableRoomNumbers`
  check in `CreateManualBooking`. A fixture that parsed but could not import
  would be worthless.
- **Every arrival is in the future** relative to `PRINTED_ON`, so no row is
  refused by the 2.0 production rule.
- Totals reconcile: 90 room-nights, 139 adults, 1 child, `25669.01` total,
  `2885.00` paid — all four printed in the footer and recomputable from the rows.
