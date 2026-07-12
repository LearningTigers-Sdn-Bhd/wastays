# Legacy Tailwind Classes in Role-Panel Pages

Last audited: 2026-07-12

## Purpose

This document tracks fixed-palette Tailwind classes that remain in the authenticated
role-panel views for Admin, Hotel, Corporate, and Guest. It is an inventory and migration
guide; it is not part of the Phase 4 navigation-component cutover.

Applying `data-theme="panel-light"` to a role-panel layout does **not** convert these
classes. It themes role-token utilities and PanelsUI components, while fixed classes keep
their existing values.

## Audit definition

The audit treats these class families as legacy when used for visual color decisions:

```text
bg-white / bg-black
bg-slate-* / text-slate-* / border-slate-* / ring-slate-*
bg-gray-* / text-gray-* / border-gray-* / ring-gray-*
bg-neutral-* / text-neutral-* / border-neutral-*
bg-layer / bg-layer-alt / border-layer-line
bg-surface / bg-surface-hover
text-neutral-text-primary / text-neutral-text-secondary
text-muted-foreground-2
```

Explicit palette classes are not automatically wrong. Keep them when a design requires a
specific color rather than a semantic role. The migration target is semantic UI chrome,
not blind search-and-replace.

## Current inventory

| Portal | Files with legacy classes | Direct page templates | Partials / streams |
|---|---:|---:|---:|
| Admin | 51 | 32 | 19 |
| Hotel | 293 | 96 | 197 |
| Corporate | 17 | 6 | 11 |
| Guest | 7 | 7 | 0 |
| **Total** | **368** | **141** | **227** |

An entry template without direct legacy classes may still render legacy partials. For
example, the Hotel and Corporate AR invoice entry templates are relatively clean, but
their headers, metrics, filters, tables, and detail partials still use fixed palettes.

## Portal findings

### Guest

Every Guest page directly contains legacy palette classes:

- `guest/dashboard/index.html.erb`
- `guest/bookings/index.html.erb`
- `guest/bookings/show.html.erb`
- `guest/refund_requests/index.html.erb`
- `guest/refund_requests/new.html.erb`
- `guest/refund_requests/show.html.erb`
- `guest/sessions/new.html.erb`

Highest concentrations are Refund Requests and Booking pages. Guest is the smallest
complete portal and is a good candidate for a later end-to-end token migration.

### Corporate

All Corporate page families are legacy directly or through rendered partials:

- Dashboard
- Corporate profile
- AR invoice index and details
- AR payment index and details
- Pay invoices
- Payment review

The largest direct concentration is `corporate_portal/ar_payments/pay_invoices.html.erb`,
followed by payment details and the profile page.

### Admin

Nearly every Admin feature area remains legacy. The largest page templates are:

| Page | Approximate legacy class matches |
|---|---:|
| API developer documentation | 125 |
| Dashboard | 122 |
| Hotel details | 116 |
| Observation Deck index | 108 |
| Reconciliations index | 84 |
| Exchange Rates | 84 |
| Margin Rules | 83 |
| Setup Fee Rules | 81 |
| Observation Deck details | 78 |
| Analytics | 76 |

Other affected areas include Hotels and onboarding, Bookings, API keys, Audit Logs,
Payouts, Plans, Refunds, Salespersons, Integrations, and Webhooks.

### Hotel

Hotel contains the largest legacy surface. High-concentration page templates include:

| Page | Approximate legacy class matches |
|---|---:|
| Inventory dashboard | 140 |
| Hotel profile edit | 139 |
| Dashboard | 138 |
| Guest records index | 126 |
| Guest registration card | 123 |
| Reports index | 122 |
| Bookings index | 122 |
| Requests index | 113 |
| In-house guests | 105 |
| Guest details | 100 |

Affected feature families include:

- Arrivals, in-house guests, checked-out guests, and guest records
- Booking index, timeline board, control panel, lifecycle drawers, and registration cards
- Inventory, room types, room status, and room groups
- Folios, routing, transactions, and booking billing controls
- AR invoices, payments, statements, and corporate accounts
- Reports, Night Audit partials, taxes, transaction codes, and GL mappings
- Settings, profiles, plans, users, roles, requests, refunds, and notifications
- Knowledge management and diagnostics

## What `panel-light` changes

Adding `data-theme="panel-light"` to a role-panel layout changes descendants that use
semantic role tokens or PanelsUI CSS variables:

```text
bg-background        text-foreground
bg-card              text-card-foreground
bg-muted             text-muted-foreground
bg-primary           text-primary-foreground
border-border        border-border-interactive
ring-ring
--status-*            --sidebar-*
```

It also sets `color-scheme: light`, affecting native browser controls. Fixed legacy
classes such as `bg-white`, `text-slate-700`, and `border-layer-line` remain unchanged.
The result is temporarily a hybrid UI: legacy fixed-color pages surrounding panel-themed
navigation and PanelsUI components.

## Recommended migration mapping

Use this table as intent guidance, not a mechanical replacement script.

| Legacy intent | Preferred semantic token |
|---|---|
| Page background | `bg-background` |
| Elevated surface | `bg-card text-card-foreground` |
| Quiet surface | `bg-muted` |
| Primary text | `text-foreground` |
| Secondary text | `text-muted-foreground` |
| Standard boundary | `border-border` |
| Interactive boundary | `border-border-interactive` |
| Focus treatment | `focus-visible:ring-ring` |
| Brand action | `bg-primary text-primary-foreground` |
| Destructive action | `bg-destructive text-destructive-foreground` |

Do not replace domain-specific report colors, financial state colors, charts, timeline
status colors, or deliberately branded surfaces without reviewing their meaning and
contrast requirements.

## Suggested migration order

1. Apply `data-theme="panel-light"` to the four role-panel layouts.
2. Complete the Phase 4 Sidebar, Breadcrumb, and Tabs migration.
3. Migrate Guest pages as the smallest full vertical slice.
4. Migrate Corporate pages, beginning with payments.
5. Migrate shared Admin shells and high-use CRUD surfaces.
6. Migrate Hotel by feature family rather than as one large rewrite.
7. Remove legacy color aliases only after repository-wide reference checks.

Each page migration should preserve behavior and test hooks, perform a light/dark contrast
check where applicable, and visually compare default, hover, focus, disabled, validation,
empty, loading, and responsive states.

## Re-running the audit

List affected files:

```sh
rg -l '(bg|text|border|ring|from|to)-(white|black|slate-[0-9]+|gray-[0-9]+|neutral-[0-9]+|layer|layer-alt|layer-line|surface|surface-hover|neutral-text-primary|neutral-text-secondary|muted-foreground-2)' \
  app/views/admin \
  app/views/hotel_portal \
  app/views/corporate_portal \
  app/views/guest \
  --glob '*.erb'
```

Before removing a legacy token or CSS rule, search the complete application, including
layouts, shared partials, helpers that build class strings, JavaScript, and tests.

## Scope boundary

Phase 4 standardizes role-panel navigation components. It does not need to migrate all
368 legacy view files. Full page-token conversion should remain a separate, incremental
frontend modernization phase.
