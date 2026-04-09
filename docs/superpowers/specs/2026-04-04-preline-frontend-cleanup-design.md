# Preline Frontend Cleanup Design

Date: 2026-04-04
Project: WAStays

## Summary

This design standardizes Preline as the frontend UI foundation for WAStays, starting with the dashboard surfaces first and extending to public pages later.

The implementation should not begin with a broad refactor. It should first stabilize and standardize the current partial Preline setup, then establish shared UI primitives, then refactor page structure around those primitives.

The chosen rollout is:
1. Stabilize Preline setup
2. Standardize dashboard shell and shared UI primitives
3. Refactor admin and hotel portal pages first
4. Extend the design system to public pages after the dashboard foundation is stable

## Current State

The current frontend uses:
- Rails ERB views
- Tailwind via `app/assets/tailwind/application.css`
- Importmap + Turbo + Stimulus
- Partial Preline usage through importmap and data/class patterns

Observed characteristics:
- Preline JavaScript is pinned in `config/importmap.rb`
- Preline JavaScript is dynamically loaded in `app/javascript/application.js`
- Preline classes and attributes are already used in several layouts and pages
- Preline CSS is not consistently applied across all layouts
- The app currently mixes custom Tailwind, custom Stimulus, and some Preline behavior
- Reuse is low; many pages are large ERB files with repeated UI structures

## Problem Statement

The frontend is not unstructured, but it is drifting toward template-heavy UI sprawl due to:
- large inline page templates
- repeated dashboard and shell markup
- inconsistent UI behavior ownership between Preline and Stimulus
- no strong shared primitive/component layer for dashboard screens
- incomplete Preline standardization

If the team refactors page organization before locking the UI system, it risks extracting the wrong patterns and creating more rework.

## Decision

Preline will become the primary UI baseline for the project.

Tailwind remains the visual styling and token layer.

Stimulus remains available, but only for app-specific behaviors that Preline should not own.

The rollout will be dashboard-first:
- Admin and hotel portal are the first migration targets
- Public pages will follow after dashboard primitives and layout patterns are stable

This gives consistent design direction across the full app without forcing a large all-at-once rewrite.

## Goals

- Establish one clear UI system for the app
- Improve frontend consistency across admin, hotel portal, and later public pages
- Reduce duplication in layouts and large ERB screens
- Make pages easier to maintain by extracting shared UI primitives
- Keep the existing Rails + ERB + Tailwind + Importmap architecture intact
- Improve dashboard polish without introducing a frontend framework rewrite

## Non-Goals

- Rewriting the app into React, Vue, or another SPA architecture
- Replacing Tailwind as the styling system
- Rebuilding all public pages in the first pass
- Performing unrelated backend refactors
- Creating speculative abstractions before patterns are proven reusable

## Recommended Architecture

### UI stack responsibilities

- **Preline**: generic interaction patterns and dashboard UI baseline
- **Tailwind theme/tokens**: brand colors, typography, spacing, shared visual language
- **Stimulus**: app-specific behaviors only
- **ERB partials/shared view building blocks**: reuse layer

### Rule of ownership

A component or interaction should have one clear owner:
- If it is a standard UI interaction supported well by Preline, use Preline
- If it is application-specific logic, keep it in Stimulus
- Avoid parallel implementations of the same kind of component across the app

## Scope and Rollout

### Phase 1 — Stabilize Preline foundation

Target files likely include:
- `config/importmap.rb`
- `app/javascript/application.js`
- `app/views/layouts/admin.html.erb`
- `app/views/layouts/hotel.html.erb`
- `app/views/layouts/application.html.erb` if public pages are prepared early for later migration

Objectives:
- make Preline loading consistent across the intended surfaces
- define a clear CSS/JS source of truth
- remove ambiguous partial setup behavior
- decide which UI patterns are Preline-owned vs custom-owned

Approved initial Preline component areas:
- overlay
- dropdown
- tabs
- accordion
- modal
- sidebar interactions

### Phase 2 — Standardize shell and shared primitives

Refactor shared layout primitives first.

Priority targets:
- sidebar navigation
- topbar/profile dropdown
- flash/toast container
- mobile bottom navigation
- page container spacing and shell rules
- page header / breadcrumb block

The goal is to make the app chrome consistent before refactoring individual screens.

### Phase 3 — Refactor dashboard screens first

Primary screen targets:
- `app/views/admin/dashboard/index.html.erb`
- `app/views/hotel_portal/dashboard/index.html.erb`

Reason:
- these files already contain the highest concentration of reusable dashboard patterns
- they are the best place to define card, section, table, and empty-state primitives

### Phase 4 — Extend to operational list/detail pages

Examples:
- bookings
- hotels
- reports
- settings
- inventory/rates pages

These should migrate after the dashboard primitives are stable.

### Phase 5 — Extend to public pages

Public pages should adopt the same design system and tokens, but not the same density as dashboard surfaces.

Public page migration should preserve a lighter experience for:
- hotel search/listings
- hotel details
- registration/login
- marketing/static pages

Consistency means shared language, not identical presentation.

## File Organization Direction

The current domain-based folder structure should remain:
- `app/views/admin/**`
- `app/views/hotel_portal/**`
- `app/views/public/**`

This is already a good high-level separation.

The cleanup should add stronger shared UI reuse, for example through directories like:
- `app/views/shared/ui/`
- `app/views/shared/navigation/`
- `app/views/shared/feedback/`
- `app/views/shared/data_display/`

These names are directional rather than mandatory. Exact naming can follow local style at implementation time, but the intent is required: repeated primitives must stop living only inside page templates.

## First Extraction Targets

The first shared extractions should be:
- sidebar nav
- topbar profile dropdown
- mobile bottom nav
- page header / breadcrumb block
- stat card
- section card
- empty state
- table shell
- icon wrapper/helper

These are already repeated or likely to be repeated across admin and hotel surfaces.

## JavaScript Direction

Stimulus should stay small and purpose-built.

Guideline:
- use Preline for generic UI interactions
- use Stimulus only when the behavior is app-specific and not a generic UI widget

Examples of app-specific behaviors that still fit Stimulus:
- tourism tax toggling
- auto-submit behavior tied to app logic
- custom toast behavior if retained

This avoids two competing systems for common UI behavior.

## Public vs Dashboard Design Rule

The full app should become visually consistent, but public pages should not be made visually identical to admin/hotel dashboards.

Shared across all areas:
- design tokens
- spacing rhythm
- typography system
- buttons/inputs/badges/tables where appropriate
- icon style

Different by area:
- dashboard surfaces can be denser and more operational
- public pages should remain lighter, clearer, and more booking-oriented

## Migration Strategy Rules

- Do not perform a giant all-at-once rewrite of all views
- Refactor in focused, high-value passes
- Keep behavior intact while improving structure and consistency
- Extract only patterns that are proven reusable
- Avoid creating abstractions for one-off markup

## Testing and Verification

Because this work affects layouts and UI structure, verification should focus on changed surfaces.

Recommended verification approach:
- verify key pages render correctly after each migration step
- run the most relevant system specs for changed areas
- add or update coverage only where behavior changes require it
- avoid claiming completion without fresh verification output for affected pages/specs

The project’s existing testing guidance should be followed:
- dashboard UI changes should use targeted system specs where appropriate
- request specs are only needed if controller behavior is changed

## Suggested Success Criteria

The migration is successful when:
- Preline is consistently configured for the chosen surfaces
- admin and hotel portal use the same core shell and primitive patterns
- large dashboard pages are thinner and composed from shared building blocks
- duplicated shell/dashboard markup is meaningfully reduced
- public pages can later be migrated using the same design system without redesigning the foundation again

## Recommended Next Step

After this design is approved, the next step is to write an implementation plan for Phase 1 and Phase 2 only:
1. Stabilize Preline foundation
2. Standardize shell and shared UI primitives

The plan should remain narrow and should not include full public-page migration in the first implementation pass.
