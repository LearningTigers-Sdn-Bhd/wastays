# Folios / Bookings Service Reorg & Rename Proposal

> Status: **Proposed** — to be executed in a dedicated branch, not the current one.
> Scope: `app/services/folios/` (40 files), `app/services/folio_routing/`, and the
> creation-time adapters in `app/services/bookings/`.
> Goal: reduce the number of top-level things a reader must track and remove
> confusingly-overlapping names. **No behaviour changes.**

## Why

`folios/` is a flat folder of 40 files and `bookings/` has ~35. The problem is not
only the count — several verbs mean nearly the same thing, so the name does not
tell you *which* service to reach for.

Same job, competing names:

| What you want | Competing service names |
|---|---|
| Make a folio | `create_folio` · `initialize_for_booking` · `recover_missing_folio` · `backfill_missing_for_operational_bookings` |
| Close a folio | `close_folio` · `close_for_checkout` · `close_no_show_folios` |
| Reopen a folio | `reopen_folio` · `reopen_for_correction` · `reopen_no_show_folios_for_reinstatement` |
| Post / compute charges | `post_category_charge` · `post_nightly_charges` · `post_early_checkout_charges` · `post_staff_transaction` · `generate_forecasted_charges` · `sync_forecasted_charges` · `refresh_open_forecasts_from_room_revenue_rules` · `nightly_charge_calculation` · `nightly_charge_reconciliation` · `process_catch_up_charges` · `forecasted_charge_lines` |
| Move money in | `record_payment_from_gateway` · `record_tourism_tax_payment` · `sync_existing_payments` · `payment_source` · `record_refund` · `refund_source` |
| Route a charge to a party | `resolve_target_folio` · `route_preview` + `folio_routing/*` + `bookings/apply_bill_to` |

`generate` vs `sync` vs `refresh` vs `calculate` vs `reconcile` vs `process` are
undefined verbs — there is no glossary that distinguishes them.

## Target structure

Group into sub-namespaces so a reader scans ~6 concepts, not 40 files:

```
folios/
  lifecycle/    create_primary · create_additional · close · reopen · rename
  charges/      post_nightly · post_category · post_early_checkout   (commands)
  forecasts/    generate · sync · refresh                            (define the 3 verbs once)
  payments/     record_payment · record_refund · record_tourism_tax
  routing/      (merge folio_routing/ + resolve_target_folio + apply_bill_to here)
  reads/        payment_source · refund_source · route_preview · forecasted_charge_lines
  maintenance/  recover_missing · backfill_missing
```

Two rules that keep it honest:

1. **One verb = one meaning**, written down. Keep `generate` (create from scratch)
   and `sync` (reconcile to current rules); rename/delete `refresh` / `reconcile` /
   `process` where they duplicate those.
2. **Value / query objects never sit among command services** — they live in
   `reads/` (or `app/queries/`).

## Naming offenders → clearer intent

| Current | Problem | Proposed |
|---|---|---|
| `initialize_for_booking` vs `create_folio` | "initialize" vs "create" is a false distinction | `CreatePrimaryFolio` (normal) vs `CreateAdditionalFolio` (manual window) |
| `apply_bill_to` (in `bookings/`) | verb + preposition fragment; wrong namespace | `FolioRouting::SponsorRoomChargesToCompany` |
| `payment_source` / `refund_source` / `route_preview` / `forecasted_charge_lines` / `charge_posting_keys` | nouns among verbs — these are query/value objects | move to `reads/` or `app/queries/` |
| `process_catch_up_charges` / `nightly_charge_reconciliation` | "process"/"reconcile" undefined; overlap with `sync_forecasted_charges` | needs a one-line glossary each |
| `backfill_missing_for_operational_bookings` | a maintenance script, not a domain op | move to `maintenance/` or a rake task |

## Blast radius (measured)

- **101 files** reference a `Folios::*` service (app + spec + config) — **321 total
  reference lines**.
- **16 more files** reference `FolioRouting::*`.
- No Zeitwerk `collapse` is configured today, so **path = constant**.

Two independent levers with very different cost:

### Lever 1 — Reorg into subfolders

| Approach | `Folios::CloseFolio` becomes | Call-site edits | Cost |
|---|---|---|---|
| **Zeitwerk `collapse`** (`Rails.autoloaders.main.collapse("app/services/folios/*")`) | stays `Folios::CloseFolio` | **0** | 1 config line + `git mv`s — near-zero risk |
| True nesting (`Folios::Lifecycle::CloseFolio`) | constant changes | up to **321 / 101 files** | high |

**Recommendation: use `collapse`** — you get the tidy folders without touching a
single call site.

### Lever 2 — Renames (always change the constant → cost = its ref count)

| Rename | Ref files | Cost |
|---|---|---|
| `apply_bill_to` → `SponsorRoomChargesToCompany` (+ move to routing) | ~6 | low |
| `create_folio` → `CreateAdditionalFolio` | 4 | low |
| `initialize_for_booking` → `CreatePrimaryFolio` | **20** | **high** — isolate in its own PR |
| `backfill_missing_for_operational_bookings` → `maintenance/…` | 1 | trivial |
| `route_preview` / `forecasted_charge_lines` / `payment_source` / `refund_source` → `reads/` | 1–5 each | low |
| `refresh_open_forecasts_from_room_revenue_rules` (verb cleanup) | 6 | low–med |

Heaviest files to re-touch if constants ever change:

| Refs | File |
|---|---|
| 8 | `spec/integration/lifecycles/exception_booking_lifecycle_spec.rb` |
| 8 | `app/controllers/hotel_portal/folio_transactions_controller.rb` |
| 5 | `app/services/bookings/finalize_no_show.rb` |
| 5 | `app/controllers/hotel_portal/folios_controller.rb` |
| 5 | `app/presenters/hotel_portal/folios/show_presenter.rb` |
| 5 | `spec/integration/lifecycles/standard_booking_lifecycle_spec.rb` |

Concentration is healthy — the top ~6 files hold most references, and ~⅓ of all
touches are specs (green-checkable immediately).

## Recommended sequencing (lowest risk first)

1. **PR 1 — reorg via `collapse`**: `git mv` into subfolders + one config line.
   Zero call-site edits. Pure structure.
2. **PR 2 — cheap renames** (`apply_bill_to`, `create_folio`, the `reads/` value
   objects, the maintenance move): each ≤6 files, mechanical.
3. **PR 3 — `initialize_for_booking` → `CreatePrimaryFolio`** alone (20 files),
   isolated for easy review.
4. **PR 4 — glossary + `refresh` / `process` / `reconcile` verb cleanup**, once the
   folders make the overlaps obvious.

## Related follow-ups (out of scope here, tracked separately)

- Three near-identical guest-folio builders (`initialize_for_booking`,
  `recover_missing_folio`, `create_folio`) should collapse onto one
  `BuildGuestFolio` primitive (DRY + one place for idempotency).
- Shared `Result` value type to replace ad-hoc `OpenStruct.new(success?: …)` shapes.
