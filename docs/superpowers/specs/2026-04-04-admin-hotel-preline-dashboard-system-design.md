# Admin + Hotel Preline Dashboard System Design

Date: 2026-04-04
Project: WAStays

## Summary

This design standardizes the full admin and hotel portal UI layer around a shared Preline-based dashboard system.

The goal is not only to clean up the dashboard home pages, but also to replace the current mix of custom-built dashboard UI pieces across admin and hotel subpages with one coherent system covering shell, navigation, cards, panels, tables, filters, forms, empty states, badges, tabs, dropdowns, and modals.

This phase applies to admin and hotel portal surfaces only. Public pages are intentionally excluded.

## Scope

### In scope
- Admin dashboard surfaces
- Hotel portal dashboard surfaces
- Admin and hotel subpages such as:
  - bookings
  - reports
  - settings
  - arrivals
  - guests
  - hotels
  - reconciliation
  - room types
  - inventory/rates
- Shared shell and navigation patterns for admin and hotel portal
- Shared dashboard component/primitives for admin and hotel portal
- Replacing custom-built dashboard UI pieces with Preline-based equivalents where appropriate

### Out of scope
- Public pages
- Marketing/landing page redesign
- Rewriting the app into React, Vue, or another frontend architecture
- Broad backend/domain refactors unrelated to UI structure
- Replacing Tailwind as the visual styling/token system

## Problem Statement

The current admin and hotel portal UI is functional, but it is still a hybrid system:
- some parts use Preline patterns
- some parts use custom Tailwind components
- some behaviors are custom Stimulus wrappers around generic UI interactions
- many dashboard and subpage screens still contain large amounts of inline, page-local UI markup

This causes several problems:
- dashboard pages and subpages do not always feel like one visual/product system
- repeated panel, table, navigation, and layout patterns are not fully standardized
- visual updates require touching many page files individually
- custom-built UI pieces are still carrying responsibility that should live in shared, reusable dashboard primitives

## Design Decision

Admin and hotel portal should share one common dashboard design system, implemented in Rails ERB using:
- Preline as the primary UI interaction/component foundation
- Tailwind tokens and utilities as the visual styling layer
- shared ERB partials for reuse
- Stimulus only for app-specific interactions that Preline should not own

The system should prioritize replacing current custom-built dashboard components with Preline-based structures wherever that improves consistency without introducing unnecessary abstraction.

## Goals

- Make admin and hotel portal feel like one coherent dashboard product family
- Replace custom-built dashboard UI pieces with a more standardized Preline-based system
- Reduce visual and structural drift between pages
- Extract shared dashboard primitives so pages become thinner and easier to maintain
- Make future dashboard/subpage work faster by giving the repo a clear set of approved UI building blocks

## Non-Goals

- Making admin and hotel visually identical in every detail
- Applying the same dense dashboard design to public pages
- Adding every Preline component whether or not the app needs it
- Creating abstractions for one-off page markup

## Core UI System

The approved dashboard system should cover these areas.

### 1. Shell
Shared dashboard shell patterns should be fully standardized using Preline-style structures where appropriate:
- sidebar
- topbar
- profile dropdown
- overlay behavior
- mobile bottom nav where it remains appropriate
- page content container spacing

### 2. Navigation
Shared navigation language should cover:
- sidebar nav groups
- active item states
- hover/focus states
- secondary nav or tabs where needed
- page-level action placement

### 3. Panels and cards
The panel system is the core of this phase.

Shared primitives should cover:
- KPI/stat cards
- standard content panels
- panel headers
- panel body spacing rules
- panel footer/action areas
- alert/attention panels
- summary panels

These should replace one-off custom panel structures where possible.

### 4. Data display
Standardized data display patterns should cover:
- table containers
- table headers
- row actions
- responsive table/card fallback patterns
- badges and status labels
- key-value display blocks

### 5. Inputs and forms
Admin and hotel subpages should share a more consistent form language using the Preline-compatible system for:
- section grouping
- labels/help text
- input spacing
- inline actions
- filter bars
- select/dropdown usage
- settings page panels

### 6. States and feedback
Shared state patterns should cover:
- empty states
- success/info/warning/error alerts
- inline notices
- modal confirmations
- loading placeholders if needed

### 7. Overlay and interaction patterns
Approved Preline interaction patterns for the dashboard system should include:
- dropdown
- sidebar/overlay
- tabs
- modal
- accordion/collapse
- tooltip

Anything outside this set should require an actual page need before being introduced.

## Admin vs Hotel Design Rule

Admin and hotel portal should share the same dashboard design language, not two different UI systems.

Shared across both:
- shell structure
- navigation styling rules
- panel/card system
- table system
- badge system
- form section patterns
- modal/dropdown/tab treatment
- spacing rhythm and typography hierarchy

Allowed to differ:
- content density by page need
- copy tone
- information architecture
- page-specific workflows

The user should feel that admin and hotel are two areas of the same product, not separate products.

## File Organization Direction

Keep the current domain page split:
- `app/views/admin/**`
- `app/views/hotel_portal/**`

Add and expand shared reusable dashboard primitives under shared view directories. The exact final directory naming can follow local repo style, but the system should provide reusable partials for:
- shell/navigation
- page headers
- panel/card primitives
- table/data display primitives
- feedback/empty states
- filter/action bars
- form section wrappers

The rule is that page-specific views should compose shared dashboard pieces rather than owning repeated UI structures directly.

## Migration Strategy

This should not be implemented as one giant rewrite.

### Recommended rollout
1. Define the shared dashboard primitive set
2. Refactor the admin and hotel dashboard home pages to use that set
3. Apply the same primitives to high-traffic subpages next
4. Continue page-group rollout until the admin and hotel portal share one consistent system

### High-priority page groups
1. dashboard home pages
2. bookings / arrivals / reconciliation / inventory views
3. settings / reports / room types / guests / hotels

## Replacement Rule

For every custom-built dashboard UI piece currently in admin/hotel pages, the implementation should ask:
1. Can this become a standardized Preline-based dashboard primitive?
2. If yes, replace it with the shared primitive/pattern.
3. If no, keep only the business-specific part custom and place it inside the shared shell/panel system.

This avoids keeping one-off dashboard component structures unless they are truly specific to the feature.

## Testing and Verification Direction

Because this redesign affects many rendered surfaces, testing should be incremental and page-group based.

Recommended verification approach:
- add or extend focused system specs for representative admin and hotel screens as page groups migrate
- run targeted system specs for changed areas after each migration pass
- use request specs only if controller behavior changes
- verify that shell/nav/critical workflows still render and navigate correctly

The implementation should avoid claiming success for any migrated page group without fresh verification output.

## Success Criteria

This phase is successful when:
- admin and hotel portal share one obvious dashboard design system
- current custom-built dashboard UI pieces are largely replaced by shared Preline-based patterns
- dashboard and subpages feel visually consistent across navigation, cards, tables, filters, and forms
- layouts and page files are thinner because repeated UI structures are extracted into shared primitives
- future dashboard/subpage changes can be made by reusing the shared system instead of rebuilding page-local UI

## Recommended Next Step

After this design is approved, the next implementation plan should focus on the first rollout slice:
1. define the shared dashboard primitive set
2. refactor admin dashboard home page to use it
3. refactor hotel dashboard home page to use it
4. only then begin applying the system to subpages in grouped passes

This keeps the implementation grounded while still aiming at the larger admin + hotel redesign goal.
