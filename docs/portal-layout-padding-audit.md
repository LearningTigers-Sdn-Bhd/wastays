# Portal Layout Padding Audit

Research snapshot for the layout padding normalization phase. Covers all four
role portals: **admin**, **hotel**, **corporate**, **guest**. No code changes —
inventory + root-cause only.

_Last audited: 2026-07-12 (branch `refactor/ui-dependency`)._

> **Phase 1 — DONE (2026-07-12).** Stripped the `mt-5` top-pad wrapper from 62
> page headers across admin / hotel / guest. Intentional `mt-5` uses (forms,
> stats `<dl>` grids, section spacing, offcanvas) were left untouched. The **T**
> flags below are historical.
>
> **Phase 2 — DONE (2026-07-14).** Conventional page headers across admin,
> hotel, corporate, and guest now render `PanelsUI::PageHeader`. The component
> uses a compact `text-base` semantic heading, exposes descriptions through an
> accessible click/keyboard popover, provides a visible caption slot for page
> context, and retains a responsive actions region. Back links, eyebrows, and
> record statuses remain visible page composition; identifiers and dates use the
> caption slot. Workspace, auth, drawer, modal, record-card, and print
> headers remain intentionally specialized.

## How the layout system works

Every portal shares the same shell: sticky navbar → optional breadcrumb bar →
`<main>` → content wrapped in **`.panel-page`**.

The standard padding lives in one place — `app/assets/tailwind/panel/page.css`:

```css
.panel-page            { @apply w-full p-4; }                         /* the standard */
.panel-page--full-height { @apply flex min-h-0 flex-1 flex-col p-0; }  /* full_height_page opt-out */
```

The shell already provides correct, uniform edge padding. **All inconsistency
comes from page templates fighting that standard.**

### Override flag legend

| Flag | Meaning | Symptom |
|------|---------|---------|
| **T** = extra top pad | header block wrapped in `mt-5` (or `pt-*`) — copied from `shared/components/_page_header` | "big padding top" |
| **X** = edge-bleed | root uses negative margin `-mx-/-m-` | "padding-x none" |
| **R** = root pad | page re-declares its own `p-*` on root | double / off padding |
| **F** = full height | `content_for :full_height_page` → `p-0` | intentional (board/folio) |

### Header situation

The original audit found two unused shared partials and hand-rolled headers on
every role page. Phase 2 now routes conventional page headings through
`PanelsUI::PageHeader`; the older shared partials remain legacy code and are not
used by the migrated portal pages. The per-portal tables below are the pre-Phase
2 inventory and retain their original custom-header classifications for history.

---

## Admin portal

| Page | Header | Custom header | Padding overridden |
|------|:--:|:--:|:--:|
| api_keys/docs | ✓ | ✓ inline | ✓ **T** |
| api_keys/index | ✓ | ✓ partial | ✓ **R** |
| api_keys/new | ✓ | ✓ inline | – |
| audit_logs/index | ✓ | ✓ partial | ✓ **R** |
| bookings/index | ✓ | ✓ inline | ✓ **T** |
| bookings/show | ✓ | ✓ inline | – |
| dashboard/analytics | ✓ | ✓ inline | ✓ **T** |
| dashboard/index | ✓ | ✓ inline | – |
| exchange_rates/index | ✓ | ✓ inline | ✓ **T** |
| hotels/edit | ✓ | ✓ inline | – |
| hotels/index | ✓ | ✓ inline | ✓ **T** |
| hotels/new | ✓ | ✓ inline | – |
| hotels/onboarding/index | ✓ | ✓ inline | ✓ **T** |
| hotels/onboarding/show | ✓ | ✓ inline | – |
| hotels/show | ✓ | ✓ inline | – |
| integrations/show | ✓ | ✓ inline | ✓ **T+R** |
| margin_rules/index | ✓ | ✓ inline | ✓ **T** |
| observation_deck/index | ✓ | ✓ inline | – |
| observation_deck/show | – | – | ✓ **R** |
| payout_batches/index | ✓ | ✓ inline | ✓ **T** |
| payout_batches/show | ✓ | ✓ inline | – |
| payouts/index | ✓ | ✓ inline | – |
| plans/index | ✓ | ✓ inline | ✓ **T** |
| profiles/edit | ✓ | ✓ inline | – |
| reconciliations/index | ✓ | ✓ inline | ✓ **T** |
| reconciliations/show | ✓ | ✓ inline | – |
| refund_policy/show | ✓ | ✓ inline | ✓ **T** |
| refund_requests/index | ✓ | ✓ inline | ✓ **T** |
| refund_requests/show | ✓ | ✓ inline | ✓ **T** |
| salespersons/index | ✓ | ✓ inline | ✓ **T** |
| setup_fee_rules/index | ✓ | ✓ inline | ✓ **T** |
| webhook_endpoints/index | ✓ | ✓ inline | ✓ **T** |

_margin_rules/create·destroy, reconciliations/retry_confirmation are turbo/confirm fragments — no header, no override._

---

## Hotel portal

The 15 `reports/*` pages are collapsed — they are identical: header ✓, inline ✓, override **T**.

| Page | Header | Custom header | Padding overridden |
|------|:--:|:--:|:--:|
| ar_invoices/index · show · aging | ✓ | ✓ partial (`_header`) | – |
| ar_payments/index · show | ✓ | ✓ partial | – |
| ar_payments/new | ✓ | ✓ inline | – |
| ar_statements/index | ✓ | ✓ partial | ✓ **T+R** |
| ar_statements/show | ✓ | ✓ partial | ✓ **T** |
| arrivals/index | ✓ | ✓ inline | ✓ **T** |
| audit_logs/index | ✓ | ✓ inline | ✓ **T** |
| workspaces/show | – | – | ✓ **F+R** (full height) |
| bookings/board/index | ✓ | ✓ partial | ✓ **T** |
| bookings/index/index | ✓ | ✓ inline | ✓ **T+X** (edge-bleed) |
| checked_out_guests/index | ✓ | ✓ inline | ✓ **T** |
| concierge_qr/show | ✓ | ✓ inline | ✓ **T** |
| corporate_accounts/index | ✓ | ✓ inline | – |
| corporate_accounts/new | ✓ | ✓ partial | ✓ **R** |
| dashboard/index | ✓ | ✓ inline | – |
| dashboard/pending_review | ✓ | ✓ inline | ✓ **R** |
| folios/index/index | ✓ | ✓ partial | ✓ **T** |
| general_ledger_maps/index | ✓ | ✓ inline | ✓ **T** |
| general_ledger_maps/edit | ✓ | ✓ inline | – |
| guests/index | ✓ | ✓ inline | ✓ **T** |
| guests/edit · new | ✓ | ✓ inline | ✓ **T** |
| guests/show | ✓ | – (section only) | ✓ **T** |
| in_house_guests/index | ✓ | ✓ inline | ✓ **T** |
| inventory_audit_logs/index | – | – | ✓ **X** (edge-bleed) |
| inventory_dashboards/index | – | – | – |
| knowledge_base/show | ✓ | ✓ inline | ✓ **T** |
| knowledge_base/new · edit | – | – | – |
| knowledge_diagnostics/index | ✓ | ✓ inline | ✓ **T** |
| knowledge_faqs · general_infos · policies /index | – | – | – |
| nearby_attractions/index | ✓ | ✓ inline | ✓ **T** |
| nearby_attractions/new · edit | – | – | – |
| night_audits/index · show | ✓ | ✓ partial | – |
| night_audits/resolve | – | – | – |
| notification_logs/index | ✓ | ✓ inline | ✓ **T** |
| onboarding_sessions/index | ✓ | ✓ inline | – |
| plans/show | ✓ | ✓ inline | ✓ **T** |
| profiles/edit | ✓ | ✓ inline | ✓ **T** |
| property_policies/edit | – | – | – |
| refund_requests/index · show | ✓ | ✓ inline | ✓ **T** |
| refund_requests/new | – | – | ✓ **R** |
| **reports/** (15 pages) | ✓ | ✓ inline | ✓ **T** |
| requests/index · archive | ✓ | ✓ inline | – |
| roles/index | ✓ | ✓ inline | ✓ **T** |
| roles/new · edit | – | – | ✓ **R** |
| room_blocks/form | ✓ | ✓ partial | – |
| room_groups/index · edit | – | – | ✓ **R** |
| room_status_board/index | ✓ | ✓ inline | – |
| room_status_board/housekeeping_requests | ✓ | ✓ partial | – |
| room_types/index | ✓ | ✓ inline | ✓ **T** |
| room_types/new · edit | – | – | – |
| settings/index | ✓ | ✓ inline | ✓ **T** |
| settings/edit | – | – | – |
| taxes_fees/show | ✓ | ✓ inline | ✓ **T** |
| taxes_fees/new · edit | – | – | – |
| transaction_codes/show | ✓ | ✓ inline | ✓ **T** |
| transaction_codes/new · edit · confirm | –/partial | – | R (confirm) |
| user_profiles/edit | ✓ | ✓ inline | – |
| users/index · new | ✓ | ✓ inline | ✓ **T** |

_Offcanvas / `actions/*` sub-templates excluded — they render inside drawers, not the panel-page._

---

## Corporate portal

| Page | Header | Custom header | Padding overridden |
|------|:--:|:--:|:--:|
| ar_invoices/index · show | ✓ | ✓ partial (`_header`) | – |
| ar_payments/index | ✓ | ✓ inline | – |
| ar_payments/show · pay_invoices | ✓ | ✓ partial | – |
| ar_payments/review | ✓ | ✓ inline | – |
| dashboard/index | ✓ | ✓ inline | – |
| profiles/show | ✓ | ✓ inline | – |

Corporate is the **most consistent** portal — AR pages already use extracted
`_header` partials, and the two dashboard/profiles `mt-5` hits are on stats
`<dl>` grids (not headers), so nothing here needed the Phase 1 strip.

---

## Guest portal

| Page | Header | Custom header | Padding overridden |
|------|:--:|:--:|:--:|
| dashboard/index | ✓ | ✓ inline | – |
| bookings/index | ✓ | ✓ inline | ✓ **T** |
| bookings/show | ✓ | ✓ inline | – |
| refund_requests/index | ✓ | ✓ inline | ✓ **T** |
| refund_requests/new · show | – | – | – |
| sessions/new | ✓ | ✓ inline | ✓ **R** (centered auth card) |

---

## Root-cause summary

1. **`mt-5` on the header block is the dominant offender** — ~65 pages carry it,
   stacking "big padding top" on top of the shell's padding. Pages without it
   (e.g. `hotel_portal/dashboard/index` vs `admin/hotels/index`) sit at the
   correct height. Single biggest lever.
2. **No page uses a shared header component** — every header is inline or a local
   `_header` partial, so nothing stops the `mt-5` habit from spreading. A
   `PanelsUI::PageHeader` (title/subtitle/actions, **no** outer margin) would
   normalize header + top-spacing in one move, aligned with the ongoing PanelsUI
   migration.
3. **Edge-bleed (`X`) — NOT a real issue (verified 2026-07-12).** The two flagged
   pages use *self-cancelling* micro-margins, not page bleed:
   `bookings/index` has `-mx-0.5`+`px-0.5` on a filter-chip row (focus-ring
   clearance), and `inventory_audit_logs` uses the standard Preline table pattern
   `-m-1.5` wrapping an inner `p-1.5` (scrollbar breathing room). A grep for
   negative margins large enough to escape `panel-page`'s `p-4` returns
   nothing. No full-bleed override exists — nothing to normalize.
4. **`F` full height (`full_height_page` → `p-0`) — one page, now padded to match.**
   Only `hotel_portal/bookings/workspaces/show` opts in; its `work_area` is a
   genuine full-height flex-fill workspace (divided `grid min-h-0 flex-1`, internal
   `overflow-y-auto` panes, `h-dvh` drawer) that requires the `full_height_page`
   wiring — removing it would collapse the internal scroll regions. So the opt-in
   stays, but its odd `px-4 md:px-0` (no top padding, desktop edge-to-edge) was
   replaced with the standard `p-5 sm:p-6` gutter so it visually follows
   `panel-page`. (Board and folios are normal `panel-page` pages — their old flags
   were the `mt-5` since fixed.)
5. **`R` root-pad — effectively a non-issue (verified 2026-07-12).** Almost every
   flag is legitimate: modal overlays (`fixed inset-0 p-4`), turbo-frame / offcanvas
   drawer content (observation_deck/show, refund_requests/new), inner card header
   bars (`px-6 py-5`), centered cards, and the guest auth page's own full-screen
   layout. The only genuine oddity was `admin/integrations/show` — a stray
   `min-h-screen flex flex-col` + redundant `pb-6` on a real panel-page child;
   simplified to `w-full space-y-6` (matches the standard). Nothing else to do.

## Final status

The original `mt-5` header top-pad was fixed in Phase 1. Phase 2 replaced
conventional inline and local-partial headers with `PanelsUI::PageHeader` across
all four portals, including newer AR, agent-account, and housekeeping headers
that had reintroduced header-owned `mt-*`, `pt-*`, or `px-*` spacing. Edge-bleed
(`X`), full height (`F`), and root-pad (`R`) remain verified as non-issues or
intentional exceptions.

### Suggested standard

Conventional pages should render `PanelsUI::PageHeader` with **zero** top margin
or horizontal page padding; `.panel-page` owns all edge padding. Concise visible
record metadata belongs in the component's caption slot, and only
`full_height_page` opts out.
