# Folios / Bookings Service Reorg & Refactor Proposal

> Status: **Complete.** PRs 1–10 delivered (revision 2); PR 9's rename was
> dropped on re-measurement — see its notes.
> Scope: `app/services/folios/` (**42** files, 5,559 LOC), `app/services/folio_routing/`
> (10 files), and the creation-time adapters in `app/services/bookings/`.
> Lens: DIP, ISP, OCP, SRP, DRY, KISS, Law of Demeter.

## What changed in revision 2

Revision 1 proposed folders and renames only, and was explicitly designed to
change zero lines of code. Reading the code turned up duplication and
encapsulation problems that foldering does not touch, and one factual error in
v1's own recommendations. Changes:

| v1 said | v2 says | Why |
|---|---|---|
| Reorg via Zeitwerk `collapse` first | **Don't use `collapse`** | It trades away `path = constant`, which v1 itself cites as a strength, and fixes nothing |
| Keep `generate` and `sync` as two defined verbs | **Delete `GenerateForecastedCharges`** | It is a 15-line pure alias for `SyncForecastedCharges`. The distinction does not exist in the code |
| `Result` type + `BuildGuestFolio` are "out of scope follow-ups" | **Core work items (M2, M4)** | They cover a live bug surface, not tidiness |
| Sequence: folders → renames → dedup | **Seams → renames → folders** | Deduplication merges several of the "competing names" on its own |
| 40 files | 42 files | Recount |

v1's blast-radius measurements and its naming analysis were sound and are kept.

## Two complaints, two different fixes

The folder/rename work and the deduplication work are not rivals. They solve
different problems, and conflating them is what made v1's sequencing wrong:

| Complaint | Fixed by |
|---|---|
| "Change one rule, edit four files" | seams (M1–M6) |
| "Silent wrong answers in money code" | seams (M2) |
| "Three names for one job" | seams — they merge — *then* renaming |
| "I can't tell which service to reach for" | renaming + verb glossary |
| "42 files is a lot to scan" | **folders** |

Seams-first takes the file count from 42 to ~43 — it removes ~800 lines of
duplication but barely dents the count. **Foldering therefore stays on the
table**; it simply lands better once the merges are done.

---

## Principle audit (measured)

### DRY — literal, byte-identical duplication

Helper bodies hashed after normalizing the hotel accessor (`@hotel` vs
`@booking.hotel`). Identical, not merely similar:

| Method | Identical copies |
|---|---|
| `transaction_code_for_tax_line` | `post_nightly_charges.rb:173`, `process_catch_up_charges.rb:222`, `forecasted_charge_lines.rb:69` (+ near-variant `post_early_checkout_charges.rb:136`) |
| `source_transaction_code_for_tax_line` | `post_nightly_charges.rb:183`, `process_catch_up_charges.rb:232` (+ variant `post_early_checkout_charges.rb:147`) |
| `room_transaction_code` | 4 files |

| Duplication | Count |
|---|---|
| `transaction_codes.find_by(system_key: …)` | **28** (`app/` + `lib/`) |
| `permitted?` — `superadmin? \|\| has_permission?` | **16 files** (10 in `folios/`); 4 byte-identical |
| Files building `OpenStruct.new(success?: …)` in folios + routing | **25** |
| Distinct result shapes | **30+** |
| `FolioOperationLog.create!` hand-rolled | **13 files** (incl. one controller) |
| Guest-folio builders duplicating `create_booking_folio!` | **3** |

### Law of Demeter — two are encapsulation breaches, not style nits

`folio_routing/apply_batch.rb:84-95` instantiates *itself* and reaches through
its own privates — four `send(:…)` plus **three `instance_variable_get(:@error)`**:

```ruby
service = new(booking:, actor: nil, routes:, …)
changes = service.send(:validated_changes)
return OpenStruct.new(success?: false, error: service.instance_variable_get(:@error)) if …
```

`BookingFolio` **deliberately** marks the reopen methods private
(`booking_folio.rb:268`), then all four callers bypass it with `send` —
`reopen_folio.rb:28,42`, `reopen_for_correction.rb:39,45`,
`reopen_no_show_folios_for_reinstatement.rb:20,37`,
`bookings/repair_no_show_tourism_tax.rb:98,112`. The privacy is fictional. It
guards a real invariant (`closed_folio_reopen_must_be_authorized`,
`booking_folio.rb:215`), so it needs a sanctioned public door, not removal.

Train wrecks: `@booking.hotel.transaction_codes.find_by(...)` (7 files),
`@booking.booking_folio.folio_transactions.payment` (`record_tourism_tax_payment.rb:57`).

### SRP

| File | LOC | Responsibilities in one `call` |
|---|---|---|
| `close_folio.rb` | 173 | permission · standard validation · direct-bill validation · credit exposure · state change · AR invoice · operation log · audit event |
| `create_folio.rb` | 150 | permission · numbering · defaults · log · **`set_primary!`** (a second operation) |
| `refresh_open_forecasts_from_room_revenue_rules.rb` | 136 | scan · **rebuild booking financial snapshots** · sync · count · audit |

### OCP

A new tax type means editing the same `case tax_line["type"]` in **4 files**. A
new bill-to party kind means editing `ResolveTargetFolio#resolve`
(`resolve_target_folio.rb:48`) — already shaped like Chain-of-Responsibility and
would take strategies cleanly.

### ISP

- `ResolveTargetFolio.call` — **9 keyword params**; most callers pass 3.
- `PostEarlyCheckoutCharges` — **4 class entry points** (`call`, `preview`,
  `pending_preview`, `projected_checkout_balance`); commands and queries mixed.

### DIP — deliberately limited

Every dependency is a concrete `Foo::Bar.call`. Full constructor injection would
be a **KISS violation**: the specs are DB-backed and green, and DI ceremony buys
little in a Rails service layer. Depend on *named seams* (M1, M2) instead. Skip
the container.

### KISS — what to leave alone

`ChargePostingKeys` (23 LOC, `module_function`) and `NextFolioNumber` (15 LOC)
are exemplary: one job, no ceremony. `NightlyChargeCalculation` as a mixin is a
sound Rails idiom. **Do not touch these** — v1's instinct to relocate
`ChargePostingKeys` into a `reads/` folder is churn without benefit.

---

## The moves

Each is independently shippable. Ranked by value ÷ risk.

**Enabler:** all 42 folio services have a matching spec in `spec/services/folios/`
(1:1, verified). Mechanical extraction is cheap to validate.

### M1 — Transaction-code resolver ★ start here

Kills 28 scattered lookups, 3 byte-identical helper triples, the
`@booking.hotel.transaction_codes` train wreck, and the 4-file OCP `case`.

No resolver exists today — `app/services/transaction_codes/` holds only
`apply_hotel_tax_rule_change.rb` and `hotel_tax_rule_change.rb`.

Prefer `TransactionCodes::Resolver.for(hotel)` with `#room_revenue`,
`#for_tax_line(tax_line)`, `#source_for_tax_line(tax_line)` over a bare
`Hotel#transaction_code(key)`. The `case` is where the duplication actually
lives; a plain key lookup would leave it copied in 4 places.

**Blast radius:** 15 app call sites in folios/bookings · 4 models · 1 controller ·
2 in `lib/tasks/`. **Risk: low** — pure extraction.

### M2 — `Result` value object (replace `OpenStruct`)

> **Delivered.** `OpenStruct` is gone from `app/services/folios/` and
> `app/services/folio_routing/`. See "Notes after implementation" at the end of
> this section.

Kills 30+ ad-hoc shapes and a silent-nil bug class in money-handling code
(`OpenStruct` answers any message, so `result.sucess?` returns `nil` — falsy,
silent).

Ruby 3.4 provides `Data.define`. Key de-risking insight:

> **Readers do not change.** A `Data` with matching member names is a drop-in for
> the ~98 sites reading `.success?` / `.error` / `.folio`. Only the **25
> constructing files** change.

The real risk is the mirror image: `Data` raises where `OpenStruct` returned
`nil`, surfacing consumers that read members the producer never sets. Those are
latent bugs today. **Mitigation:** land per-family — lifecycle results first
(the most uniform shape, 8 files), then transactions, then routing, with a full
`bin/test` between slices. **Risk: medium**, mechanical.

#### Notes after implementation

Landed in four commits — lifecycle, postings, routing/batches, reports — each
with a full `bin/test` between. Three findings worth carrying forward:

**One shared result per family was too coarse.** M2 proposed
`TransactionResult(:transaction, :transactions)` for everything that posts. Move
and split got their own shapes instead: a `MoveResult` that nil-filled
`source_transactions` would reintroduce exactly the laxity being removed. Seven
result types and six report types in total, each naming only what it produces.
The reports — `RoutePreview::Report`, `BookingCheckoutReadiness::Report`,
`NightlyChargeReconciliation::Report` — are plain `Data`, not
`ApplicationResult`: they have no failure mode, and forcing one would invent it.

**The mutation, not the read, was the real find.** `post_staff_transaction`
wrote `result.tax_transactions =` onto the result it got back from
`InsertTransaction` — a member `InsertTransaction` never declares. Only
`OpenStruct` permits that; the caller was conjuring the field into existence.
`Data` is frozen, so it is now `result.with(...)` against a declared member.
Similarly `ApplyGroupBatch` had one `failure` serving both its preview and its
apply, so a failed preview was structurally a batch result — safe only because
`success? && review_required?` short-circuits before reading a member the
failure never had.

**Dropping `require "ostruct"` breaks specs that never required it.** Four
specs used `OpenStruct` while relying on the service under test to load it.
They pass in a batch run — some other spec loads `ostruct` first — and fail
only when run alone. **Sweep each spec file individually, not just the
directory**, or this hides. Roughly 20 more spec files are in this position
today, held up by the ~100 unconverted services elsewhere in `app/services/`;
they become failures as the conversion spreads. That is the main cost of any
app-wide follow-up.

### M3 — Public reopen-authorization API

Replace the private pair with one public block method on `BookingFolio`:

```ruby
folio.reopening_for_correction { folio.update!(status: "open", …) }
```

All four call sites already hand-roll this authorize/ensure-clear sandwich, two
of them with a bare `ensure` inside a block (`reopen_folio.rb:41`,
`reopen_for_correction.rb:44`) — subtle and easy to get wrong.

**Blast radius:** 1 model + 4 services. **Risk: low.**

### M4 — `BuildGuestFolio` primitive

Kills 3 duplicated builders and — the real prize — **3 rival idempotency
strategies for the same race**:

| Service | Race strategy |
|---|---|
| `initialize_for_booking.rb:25` | rescues `RecordNotUnique` **and** `RecordInvalid`, re-reads, re-raises if absent; conditional on `lock:` |
| `recover_missing_folio.rb:45` | rescues `RecordNotUnique` only |
| `create_folio.rb:35` | rescues `RecordInvalid` → generic failure; no re-read |

Highest-value **correctness** item in the list.

#### Scope is smaller than it looks — `lock:` is maintenance-only

`initialize_for_booking`'s `lock:` selects between two failure strategies:
`lock: true` wraps in `booking.with_lock` and runs the rescue/reload/return-the-
winner recovery; `lock: false` does none of it, because the caller's transaction
would be poisoned by a duplicate insert (comment at line 17).

Across all 8 app call sites, **7 pass `lock: false`**:

| `lock:` | Call sites |
|---|---|
| `false` | `transition_status.rb:86,161` · `create_manual_booking.rb:158` · `finalize_no_show.rb:37` · `reinstate_reservation.rb:51` · `confirm_booking.rb:167` · `confirm_group_booking.rb:128` |
| default (`true`) | `backfill_missing_for_operational_bookings.rb:28` — **only one** |

The single `lock: true` production caller is the maintenance backfill this
proposal already relocates. Specs use the default because they call the service
standalone, so the branch stays well covered.

**All 7 `lock: false` callers verified as running inside a transaction** — the
line-17 contract holds, none is bare:

- 4 hold an explicit `@booking.with_lock` (`transition_status` ×2,
  `finalize_no_show`, `reinstate_reservation`).
- 2 create the booking *inside* the transaction (`create_manual_booking`,
  `confirm_group_booking`), so no concurrent creator for that booking can exist.
- 1 serializes on `@quote.with_lock` (`confirm_booking:13`) rather than the
  booking — correct granularity, since the race being prevented is two confirms
  of one quote. Its `existing_booking` branch (line 18) is the idempotent
  re-entry path.

#### Consequence

`BuildGuestFolio` needs **one** behaviour: the plain insert, no rescue, caller
supplies the transaction — the `lock: false` semantics 7 of 8 callers already
use. Locking + recovery becomes a thin opt-in wrapper for the one maintenance
caller. `recover_missing_folio` keeps its own `RecordNotUnique` wrapper for the
night-audit blocker path.

That reduces the work from "reconcile three rival concurrency strategies" to
"extract one insert, keep one small wrapper" — and the hot paths never touch the
branch that would be riskiest to change.

**Do after M2**, so all three return one comparable shape. **Risk: low.**

### M5 — `SystemActor` + `Authorizable` concern

> **Delivered as `Authorizable` only. `SystemActor` was not built — see
> "Correction after implementation" at the end of this section.**

**Decided:** null-object `SystemActor`; drop the `respond_to?` guards.

Kills 16 copies of the permission idiom **and** three competing system-actor
bypasses. `close_folio`, `rename_folio`, `reopen_folio`, `update_folio` have
byte-identical `permitted?` bodies; `create_folio` differs only by its
`skip_authorization` early return.

#### Why not keep the `respond_to?` guards

```ruby
@user&.respond_to?(:superadmin?) && @user.superadmin? ||
  @user&.respond_to?(:has_permission?) && @user.has_permission?(PERMISSION, hotel: @hotel)
```

- `has_permission?` is defined on **`User` only** (`user.rb:44`). `superadmin?` is
  on `User` (`user.rb:32`) **and `ApiKey`** (`api_key.rb:19`).
- `booking_folios.created_by_id` / `closed_by_id` are **FKs to `users`**
  (`schema.rb:2063-2064`) — a non-`User` actor cannot be persisted on a folio.
- The guard therefore defends against a type the DB rejects, while making that
  type **silently pass**: `ApiKey#superadmin?` is `bearer.nil?`, so an unbound key
  would get full folio permission and skip the `has_permission?` branch entirely.
  No live path does this today; the guard enables it rather than preventing it.

Duck-typing a permission check means anything that quacks becomes an admin.

#### Why `nil` is not workable as "system"

`permitted?` returns **false** for `nil`, so every system path invented its own
hole — three so far:

| Mechanism | Where |
|---|---|
| `skip_authorization: true` | `create_folio.rb:136` |
| `system_folio_initialization` + `posting_source` **string equality** | `initialize_for_booking.rb:104` |
| no check at all | various |

The string-matching one has **already failed** — see *Related, tracked separately*.

#### Allowlist, not blanket

A blanket-permission `SystemActor` is `skip_authorization` with a nicer name: it
centralizes the three bypasses (good) but grants exactly what they granted, so it
fixes nothing. **The allowlist is where the value is.**

It is also small and derivable, so it stays behaviour-preserving. The complete
set of folio-touching system callers:

| Caller | Reaches |
|---|---|
| `booking_engine/confirm_booking.rb:169` | `InitializeForBooking` |
| `booking_engine/confirm_group_booking.rb:130` | `InitializeForBooking` |
| `channel_managers/ingest_booking_service.rb:172` | `InitializeForBooking` |
| `channel_managers/ingest_group_booking_service.rb:264` | `InitializeForBooking` |
| `booking_billing_parties/manage_company.rb:84` | `CreateFolio` |
| `folios/record_payment_from_gateway.rb:32` | `InsertTransaction` |
| `folios/post_early_checkout_charges.rb:24,35` | preview only — read-only |

That resolves to **`manage_folio_windows`** plus whatever `InsertTransaction`
gates. Note `ResolveTargetFolio::PERMISSION` is *not* needed — it gates manual
override only, not normal routing.

Two permissions are then **excluded by construction**, and both should be:

- `override_corporate_credit_limit` (`close_folio.rb:8`) — exists specifically to
  force a deliberate human decision **with a reason**.
- `post_folio_corrections` (`reopen_for_correction.rb:7`) — requires a reason
  **and** a note.

Granting either to a null object would be exactly backwards. A blanket
`SystemActor` would grant both.

#### Shape

`permitted?` collapses to `actor.can?(PERMISSION, hotel:)`. `User` and
`SystemActor` each answer honestly; anything else raises `NoMethodError` at the
boundary instead of silently passing.

**Serialization caveat:** `financial_audit_events` has a polymorphic `actor_type`
(`schema.rb:740`), so `SystemActor` can be recorded there as-is — but folio
`created_by` / `closed_by` are FK-to-users, so it must serialize as `nil` there.
Be deliberate about this rather than discovering it at runtime.

**Risk: low.** Behaviour-preserving given the derived allowlist.

#### Correction after implementation

**`SystemActor` was not built, because the premise above is wrong.** The three
"competing system-actor bypasses" are not three bypasses of the same thing:

| Claimed bypass | What it actually bypasses |
|---|---|
| `system_folio_initialization` (`initialize_for_booking`) | `NightAudits::OperationalChangeGuard` — an **operational** guard, not a permission check. `InitializeForBooking` has no permission check to bypass |
| "no check at all" | same — these paths never had a permission check |
| `skip_authorization` (`create_folio`) | a real permission check, but **not by a system caller** |

The single caller of `skip_authorization` is
`BookingBillingParties::ManageCompany`, which passes `actor: current_user` — a
real staff member, already gated on `manage_bookings` by
`workspace_actions_controller#authorize_manage_bookings!`. Creating the company's
folio is part of adding the billing party, so it deliberately does not also
demand `manage_folio_windows`. Replacing that actor with a null object would have
**lost audit attribution**: `created_by` and the `FolioOperationLog` actor both
record it.

So there is no permission path that wants a null actor. Building `SystemActor`
would have meant inventing an actor for a problem the permission layer does not
have, and the allowlist — the part with the actual value — would have had nothing
to gate.

**What was delivered instead:** the `Authorizable` concern
(`app/services/authorizable.rb`), replacing the idiom in **14** methods across 11
files. Two findings drove its shape:

- The `superadmin?` clause is **dead for Users** — `User#has_permission?`
  already returns `true` for a superadmin (`user.rb:45`). The only actor that
  clause can decide alone is a non-`User`.
- Which is the hole: `respond_to?` made authorization duck-typed. `ApiKey`
  answers `superadmin?` as `bearer.nil?` and has no `has_permission?`, so an
  unbound key passed on the first clause and never reached a permission lookup.

`actor_permits?` denies `nil` exactly as before, and raises `UnsupportedActor`
for anything that is neither `nil` nor a `User`. Also swept in
`FinancialControls::PostingGuard#override_permission?`, which carried the same
idiom while gating `override_financial_date_lock` — the most sensitive
permission of the set.

The two permissions M5 wanted excluded by construction
(`override_corporate_credit_limit`, `post_folio_corrections`) remain
unreachable without a real user, which was the goal.

### M6 — Fix `ApplyBatch.preview`

Extract shared validation into a `RoutingChangeSet` value object that both
`.call` and `.preview` build. `preview` then reads it normally, and `@error`
becomes a return value rather than smuggled state.

**Blast radius:** 1 service + 2 consumers
(`hotel_portal/bookings/workspace_actions_controller.rb:200,227`,
`folio_routing/apply_group_batch.rb:52,91`). **Risk: low–medium** —
`apply_batch.rb` is 12.7 KB and thinly specced.

### M7 — Delete `GenerateForecastedCharges`

A 15-line class whose entire body is `Folios::SyncForecastedCharges.call(...)`.
Two app callers (`initialize_for_booking.rb:51`, `recover_missing_folio.rb:39`),
plus its own spec file.

This is also the evidence that v1's proposed glossary was wrong: `generate` and
`sync` are not two verbs with different meanings here, they are one call.
**Risk: trivial.**

---

## Naming & foldering — revised

The rename analysis from v1 holds. What changes is *when*.

### Renames worth doing regardless of sequencing

| Current | Problem | Proposed | Refs |
|---|---|---|---|
| `apply_bill_to` (in `bookings/`) | verb + preposition fragment; wrong namespace | `FolioRouting::BillRoomChargesToCompany` | 2 |
| `backfill_missing_for_operational_bookings` | a maintenance script, not a domain op | `Folios::Maintenance::…` | 3 |
| `route_preview` · `forecasted_charge_lines` | nouns among verbs — reads, not commands | `Folios::Reads::…` | 8 |
| `payment_source` · `refund_source` | nouns among verbs | **left in place** — see PR 8 notes | — |

#### Notes after implementation (PR 8)

**Ref counts were overestimated.** `apply_bill_to` was measured at ~6 refs; it
had one app caller and its spec. All three renames together came to 15 files,
not the ~18 the sequencing table implied.

**`Sponsor` was the wrong verb, `Corporate` the wrong noun.** The codebase has
no "sponsor" anywhere, while `bill_to` is established across 7 files including
the checkout and booking-creation views. And `corporate` names the *account*
record (`hotel_corporate_account`), while `company` names the *payer kind*
(`payer_type` enum, `BookingBillingParties::ManageCompany`). Routing targets
the payer kind. Hence `BillRoomChargesToCompany`.

**M2 missed this file because of its namespace.** `apply_bill_to` still built
`OpenStruct` — the M2 sweep covered `folios/` and `folio_routing/`, and this
lived in `bookings/`. Moving it in without converting would have reintroduced
`OpenStruct` to a namespace M2 declared clean, so the rename carried a
`FolioRouting::BillingResult` conversion. It also *returned*
`ManageCompany`'s `OpenStruct` directly on the party-failure path; that now
wraps into its own typed failure. `BookingBillingParties::ManageCompany`
itself is still `OpenStruct` — out of scope, and one of the ~100 unconverted
services M2's notes flag.

**`payment_source` / `refund_source` did not belong in `reads/`.** They are
frozen `SOURCES` catalogs answering `.fetch` / `.options` / `.valid?` — no DB,
no booking, nothing read. Filing them as reads would mislabel them, and the
only honest alternative (`catalogs/`) meant inventing a bucket and touching 9
refs across presenters, controllers and two report services to fix nothing.
Left where they are.

**`app/queries/` was not the destination.** It holds `*Query`-suffixed AR-scope
builders (`HotelsQuery`, `RoomTypesQuery`) — a different convention.

**This is the dry run for PR 10.** `reads/` and `maintenance/` are the first
true-nested subfolders under `folios/`, no `collapse`. If two folders already
grate, that is cheap evidence against the full seven.

### The verb glossary — do this now, it is free

**Done (PR 1): `docs/folios-service-verbs.md`.**

`generate` · `sync` · `refresh` · `calculate` · `reconcile` · `process` had no
written distinction. One page of documentation makes every future naming
decision obvious. **Correction from v1:** do not enshrine `generate` vs `sync` —
M7 shows they are the same operation, and the glossary records `generate` as
retired.

### Renames to defer until after the seams work

The three creation services (`create_folio`, `initialize_for_booking`,
`recover_missing_folio`) compete because they duplicate one insert. Renaming
them to `CreatePrimaryFolio` / `CreateAdditionalFolio` / `RecoverMissingFolio`
produces three crisp, distinct-sounding names for what is **one** job done three
ways — **the good naming would hide the duplication**, making it look
deliberate. Merge first (M4), then name what remains.

Same logic applies to `initialize_for_booking` → `CreatePrimaryFolio`, v1's most
expensive rename at **20 files**. Its cost may shrink substantially after M4;
re-measure before committing to it.

#### Re-measured after PR 6 — rename dropped (PR 9)

It did not shrink. M4 extracted the insert but left all 8 callers pointed at
the orchestrator: **25 files, 37 reference lines**, up from the ≤20 estimate.
Three reasons not to spend them:

- **The proposed name now collides with what M4 landed.**
  `initialize_for_booking.rb:59` calls `Folios::BuildPrimaryFolio`, so the
  rename would produce `CreatePrimaryFolio` → `BuildPrimaryFolio`. "Create"
  versus "build" is not a distinction a reader can hold. It would also sit
  beside `CreateFolio`, where the glossary reserves `create` for a folio
  someone explicitly asked for — two `create`s differing only by noun.
- **`Create` is factually wrong.** The service is idempotent: it returns the
  existing folio when one is present (line 46), and in lock mode re-reads and
  returns the concurrent winner. On re-entry it creates nothing.
  `EnsurePrimaryFolio` would be the honest name if the rename were worth
  doing.
- **The current name is already defined and accurate.** The glossary (PR 1)
  gives `initialize` a real meaning — a step inside another workflow rather
  than a request in its own right — and all 8 callers match it.

The only genuine confusion M4 introduced was an undocumented verb. **PR 9
therefore adds `build` to the lifecycle verbs** and notes `initialize`'s
idempotency, in one file rather than 25.

### Foldering — optional, and not via `collapse`

Target layout, if pursued, after the seams work:

```
folios/
  lifecycle/    build_guest_folio · create · close · reopen · rename
  charges/      post_nightly · post_category · post_early_checkout
  forecasts/    sync · refresh
  payments/     record_payment · record_refund · record_tourism_tax
  routing/      (merge folio_routing/ + resolve_target_folio + apply_bill_to)
  reads/        payment_source · refund_source · route_preview · forecasted_charge_lines
  maintenance/  recover_missing · backfill_missing
```

#### Notes after implementation (PR 10)

**The sketch above covered 15 of 46 files and was wrong about the buckets.**
Two of the largest families had no home in it: `transactions/` (10 files — the
correction verbs the glossary already grouped) and `checkout/` (4). The 8
result `Data` types M2 added after the sketch was written had none either;
they live beside the service that returns them.

Final layout, and the four judgement calls:

| Folder | Files | |
|---|---|---|
| `routing/` | 21 | `folio_routing/` **merged in** as `Folios::Routing`, per the sketch |
| `lifecycle/` | 12 | |
| `transactions/` | 10 | not in the sketch |
| `charges/` | 7 | incl. `ChargePostingKeys` |
| `payments/` | 6 | incl. `PaymentSource`/`RefundSource`, which PR 8 left at root |
| `checkout/` | 4 | not in the sketch |
| `maintenance/` | 3 | `RecoverMissingFolio` joined the backfill |
| `forecasts/` · `reads/` | 2 each | |

`NextFolioNumber` left the namespace entirely: it wraps
`HotelCounter.increment!` with `type: "folio"`, exactly as
`DocumentIdentifiers::HotelReferences` does for reservation and receipt
numbers, so it is now `DocumentIdentifiers::NextFolioNumber`. That resolves
"Not recommended: relocating `NextFolioNumber`" — the objection was to
inventing a `reads/` home for it, not to filing it with the other counters.
`ChargePostingKeys` stayed in `folios/`, in `charges/`.

**Cost was 180 files, not 101** — 399 qualified references rewritten
mechanically, plus 5 bare cross-bucket references (an `include`, two constant
reads, a `resolve` call) fixed by hand. The 10 other bare hits the scan
flagged were locally-nested `Result` constants — false positives, and the
reason to review that list rather than run the rewrite blind.

**Two things worth knowing for any future move of this size:**

- `bin/rails zeitwerk:check` validates the constant/path alignment in seconds
  and is the fastest signal that the re-nesting is right.
- **`spec/services/folio_routing/` was in no `bin/test` domain**, so its 18
  specs only ran under `bin/test all`. Moving them under `spec/services/folios/`
  put them in `financials`. Fifteen other spec directories are still in that
  position, including `spec/services/transaction_codes/`. `next_folio_number_spec`
  would have fallen into the same hole, so `spec/services/document_identifiers`
  was added to the `financials` domain.

One latent spec break surfaced: `spec/requests/admin/refund_requests_spec.rb`
stubbed `RecordRefund` with an `OpenStruct` and relied on another spec to load
`ostruct`. It now builds the real `TransactionResult`. It fails identically on
the pre-PR tree when run alone, so this is M2's documented trap, not fallout
from the move — but the move is what made it fail in a domain run. **19 more
specs are still in that position.**

**Do not use Zeitwerk `collapse`.** It buys folders at the cost of
`path = constant` — a navigation property v1 itself identifies as currently true
and useful. If the folders are worth having, they are worth the true nesting;
if they are not worth 321 reference-line edits, they are not worth breaking
navigation for either.

## Blast radius (from v1, verified)

- **101 files** reference a `Folios::*` service (app + spec + config) — **321
  reference lines**. **16 more** reference `FolioRouting::*`.
- No Zeitwerk `collapse` configured today, so **path = constant**.
- Concentration is healthy — the top ~6 files hold most references, and ~⅓ of
  all touches are specs (green-checkable immediately):

| Refs | File |
|---|---|
| 8 | `spec/integration/lifecycles/exception_booking_lifecycle_spec.rb` |
| 8 | `app/controllers/hotel_portal/folio_transactions_controller.rb` |
| 5 | `app/services/bookings/finalize_no_show.rb` |
| 5 | `app/controllers/hotel_portal/folios_controller.rb` |
| 5 | `app/presenters/hotel_portal/folios/show_presenter.rb` |
| 5 | `spec/integration/lifecycles/standard_booking_lifecycle_spec.rb` |

## Sequencing

| PR | Work | Files | Risk | Status |
|---|---|---|---|---|
| 1 | M7 delete alias · verb glossary | 3 | trivial | **done** |
| 2 | M1 transaction-code resolver | ~20 | low | **done** |
| 3 | M3 reopen API | 5 | low | **done** |
| 4 | M5 `Authorizable` concern (no `SystemActor` — see M5 correction) | 11 (+1 new) | low | **done** |
| 5 | M2 `Result`, family by family — 4 slices | 25 | med | **done** |
| 6 | M4 — landed as `BuildPrimaryFolio` | 3 | low | **done** |
| 7 | M6 `ApplyBatch` — landed as `RoutingChangeSet` | 3 | low–med | **done** |
| 8 | Cheap renames (`apply_bill_to`, `reads/`, maintenance) | 15 | low | **done** |
| 9 | `initialize_for_booking` rename — **dropped**, glossary entry instead | 1 | low | **done** |
| 10 | Foldering — true nesting, not `collapse` | 180 | high | **done** |

PRs 1–4 are mechanical and independently revertable. PR 5 needs a full
`bin/test` between slices. PRs 8–10 are optional and can stop at any point.

## Not recommended

- **Zeitwerk `collapse`** — see above.
- **Relocating `ChargePostingKeys` / `NextFolioNumber`** — exemplary as-is.
- **Constructor-injecting collaborators** — DIP ceremony with no payoff given
  DB-backed specs.
- **Splitting `close_folio.rb` in this round** — real SRP violation, but the
  direct-bill path is intricate and it blocks nothing. Revisit after M2 gives it
  a typed result.

## Decisions (all resolved — no blockers remain)

1. ~~**M5** — keep `respond_to?`-guarded permission checks, or move to a null
   actor?~~ **Resolved: `SystemActor` null object with a derived allowlist.**
   See M5. PR 4 unblocked.
2. ~~**M2** — `Folios::Result`, or app-wide?~~ **Resolved: a shared *recipe*,
   not a shared class.** `Concierge::Result` uses named domain members;
   `AiConcierge::…::Result` uses a generic `payload`. Named members win — they
   are what keeps ~98 reader call sites unchanged, making M2 a 25-file job. A
   generic `payload` would turn `result.folio` into `result.payload[:folio]`
   everywhere and make it a 98-file job for no gain. Shape:

   ```ruby
   module ApplicationResult
     def self.define(*members)
       Data.define(:"success?", :error, *members) do
         def self.success(**attrs) = new(success?: true, error: nil, **attrs)
         def self.failure(error, **attrs) = new(success?: false, error:, **attrs)
       end
     end
   end

   module Folios
     Result            = ApplicationResult.define(:folio)
     TransactionResult = ApplicationResult.define(:transaction, :transactions)
   end
   ```

   Verified on Ruby 3.4.7: `Data.define(:"success?")` is legal, and `Data` raises
   `NoMethodError` where `OpenStruct` returned `nil`. Use `Data`, not `Struct` —
   results should be frozen. **Implementation wrinkle:** `Data` requires every
   member at construction, so `.failure` must nil-fill unspecified members.
   Leave `Concierge` and `AiConcierge` as they are; converge later if it pays.
   (No `ApplicationService` base class exists today — verified.)
3. ~~**M4** — is `initialize_for_booking`'s `lock:` parameter vestigial?~~
   **Resolved: maintenance-only, and all 7 `lock: false` callers verified safe.**
   See M4. Risk downgraded medium → low.

## Related, tracked separately

- **Group booking confirmation is blocked during a night audit.**
  `initialize_for_booking.rb:107` skips the night-audit guard only when
  `posting_source == "booking_confirmation"`. `confirm_booking.rb:172` matches;
  `confirm_group_booking.rb:131` passes `"group_booking_confirmation"` and does
  not. Both are system confirmations with `user: nil` and
  `system_folio_initialization: true`, so while an audit runs, single booking
  confirmation succeeds and group booking confirmation raises
  `OperationalChangeBlocked`. M5 removes this class of bug by construction, but
  the defect should be fixed on its own timeline rather than waiting for the
  refactor.
- `lib/tasks/generate_hotel_dataset.rake:399` looks up
  `system_key: "room_charges"`, but every app-side lookup uses `"room_revenue"`.
  Likely a latent bug in the dataset task — found while enumerating M1 call sites.
