# Pagination migration proposal

Date: September 6, 2026

Status: Phase 1 and the Pagy-only Nova redesign are implemented. Validation results and remaining acceptance work are recorded below.

## Recommendation

Migrate all Kaminari pagination to Pagy 43.6.2 while keeping the current user behavior.

Migrated pages use the compact shadcn Nova style through `PanelsUI::Pagination`. Unmigrated Kaminari pages keep their existing design until migration.

Use Pagy's `:offset` paginator for the initial migration. Evaluate other pagination methods after measuring slow pages.

Estimated effort: **5.5–8.5 working days** for one developer familiar with WAStays. Difficulty: **medium**.

This estimate covers implementation, regression tests, fixes, and acceptance checks. It assumes a healthy test baseline.

## Version and compatibility

The project currently uses Kaminari 1.2.2, Ruby 3.4.7, and Rails 8.1.3.1.

This proposal targets the new Pagy 43 API, not an older Pagy version. Pagy 43.6.2 was released on August 24, 2026.

Pagy 43.6.2 requires Ruby 3.3 or later. The project's Ruby version meets that requirement. Focused and non-browser suites support application compatibility.

The proposed dependency is:

```ruby
gem "pagy", "~> 43.6.2"
```

This constraint permits patch updates within version 43.6. Version 43.6.2 fixes an array-pagination overflow issue relevant to this project.

The current API uses `Pagy::Method` and `pagy(:offset, collection, ...)`. Pagination metadata and displayed records are separate objects.

Sources: [RubyGems release](https://rubygems.org/gems/pagy/versions/43.6.2), [Pagy changelog](https://ddnexus.github.io/pagy/changelog/), and [migration guide](https://ddnexus.github.io/pagy/guides/migration-guide/).

## Scope

Replace all Kaminari-dependent pagination across the Admin, Hotel, Corporate, and Guest portals.

Keep the following behavior:

- Existing responsive behavior with a new Nova appearance on migrated pages.
- Desktop page numbers and First, Previous, Next, and Last controls.
- Mobile page indicators.
- Existing page sizes and the Admin hotel page-size selector.
- Search terms, filters, selected tabs, and independent page parameters.
- Turbo frame navigation and browser history behavior.
- Report totals, financial calculations, and export selection behavior.
- Existing account and hotel access boundaries.

Some pagination markup must change because it depends on Kaminari. The replacement uses the portal's Nova component design.

The staged migration intentionally shows two designs. Admin API Keys demonstrates Pagy with Nova styling. Admin Hotels retains the existing Kaminari styling.

No database migration or data backfill is expected for the gem replacement.

The initial scope excludes report query redesign, new cursor navigation, infinite scrolling, and unrelated UI changes. Custom pagination without Kaminari stays outside this migration.

Do not change the seven Kaminari templates during the Pagy component redesign. They remain the visual baseline for unmigrated pages.

## Affected pages

The list includes pages, tabs, and shared sections. Some sections share the same pagination code.

| Area | Affected pages or sections |
|---|---|
| Hotel operations | Front Desk Bookings, Arrivals, In-house, Departures, and Checkout; guest directory and guest booking history; Folios and attention list; Room Types; Conversations; Nearby Attractions |
| Hotel finance | Corporate Accounts; invoices; payment records; statement list and statement details; e-invoice submissions |
| Hotel reports | Financial performance and breakdown; payout history; Daily Report charge register and Cashier Activity; channel settlements; journal batches; guest-report tables, including registration cards, boat transfers, and meal preparation; night-audit history |
| Hotel logs | Audit logs, notification logs, and inventory audit-log pagination |
| Admin | Hotels; Bookings; Attractions; API Keys; Audit Logs; Observation Deck events; Margin Rules; Setup Fee Rules; Payouts; pending and paid Payout Batches; Reconciliations; Refund Requests |
| Corporate portal | Invoices; payment history; statement list and statement details |
| Guest portal | Bookings and refund-request lists |

Affected means the pagination code needs changing. It does not mean the whole page needs rebuilding.

## Source inventory

The source review found:

| Item | Footprint |
|---|---|
| Kaminari pagination setup | 49 `.page(...)` calls across 37 files |
| Setup locations | 24 controllers, 10 presenters, 2 queries, and 1 helper |
| Array pagination | 11 `Kaminari.paginate_array` calls across 8 files |
| Navigation rendering | 38 calls across 37 view files, plus the Observation Deck component |
| Shared navigation | 7 custom Kaminari templates |
| Existing test references | Pagination references across 18 spec files |

These counts overlap. Test references do not prove complete regression coverage.

Key implementation files include:

- `Gemfile` and `Gemfile.lock`.
- `app/views/kaminari/`.
- `app/controllers/hotel_portal/front_desk_controller.rb`.
- `app/controllers/hotel_portal/reports_controller.rb`.
- `app/helpers/hotel_portal/reports_helper.rb`.
- `app/presenters/hotel_portal/folios/index_presenter.rb`.
- Hotel and Corporate accounts-receivable presenters.
- `app/queries/guests/guest_bookings_query.rb`.
- `app/queries/hotel_portal/guest_registration_cards_query.rb`.
- `app/views/hotel_portal/reports/_table_pagination.html.erb`.

## Implementation design

### Shared navigation

Use one shared `PanelsUI::Pagination` component for migrated pages. The source review found no earlier PanelsUI pagination component.

The component receives a Pagy object and renders compact Nova navigation. It uses portal semantic tokens, the shared button contract, and `app_icon`.

Basic pagination remains server-rendered. No additional JavaScript is planned for this approach.

The component must preserve accessible labels, keyboard navigation, visible focus, disabled states, and the current-page indicator.

### Records and pagination metadata

Kaminari attaches pagination methods to the record collection. Pagy returns the records and pagination metadata separately.

| Current contract | Proposed contract |
|---|---|
| Views read `collection.total_pages` | Navigation reads `pagy.pages` |
| Views read `collection.current_page` | Navigation reads `pagy.page` |
| Presenters expose paginated collections | Presenters expose rows and pagination metadata separately |
| Some query objects apply pagination | Query objects return scopes; callers apply pagination |

Presenters currently receive parameters without a request object. Implementation must pass URL context explicitly or apply pagination in their callers.

Use the smallest shared interface needed. Do not recreate Kaminari's collection API through a large compatibility layer.

### Page parameters and limits

Preserve existing page keys, including `arrival_page`, `checkout_page`, `cashier_page`, `pending_page`, and `paid_page`.

Each section must retain its own pagination state. Changing one section must not reset another section or discard filters.

Preserve current page-size rules explicitly. Pagy's default page size must not silently replace existing limits.

### Reports and exports

Apply pagination only to the displayed rows. Totals must retain their existing calculation scope.

Full exports must retain all applicable rows. Selected exports must retain the selected records across pages.

Statement balances and report group totals must not become page-only totals.

## Phase 1: Core and shared setup plan

Status: Core setup and the Admin API Keys pilot are implemented. Rubyzip is updated, and a new full CI run is pending.

Estimated effort: **1.5–2 working days**, including the pilot and focused tests. This work is part of the full 5.5–8.5 day estimate.

### 1. Add the dependency and configuration

Add `gem "pagy", "~> 43.6.2"` and update the lockfile through Bundler. Keep Kaminari installed while unmigrated pages still use it.

Create `config/initializers/pagy.rb` with a small set of shared options:

- Default limit: 25 records.
- Client limit override: disabled with `max_limit: false`.
- Page key: retain Pagy's `page` default.
- Out-of-range pages: use offset pagination's empty-result behavior, covered by tests.
- Freeze `Pagy::OPTIONS` after configuration.

Every migrated caller must still supply its existing limit explicitly. This preserves the current 15, 20, 25, 30, and 50-row use cases.

The Admin hotel page-size selector continues using its existing normalization method. The controller passes that approved value as `limit:`.

Do not add legacy `Pagy::Backend`, `Pagy::Frontend`, or extras configuration. Do not enable Pagy development tools or JavaScript assets for this phase.

### 2. Expose the current Pagy API

Add `include Pagy::Method` to `ApplicationController`. All four portal base controllers inherit from it.

Use Pagy's native pair of return values. The application does not need a replacement collection class or a generic pagination service at this stage.

Proposed controller usage:

```ruby
@pagy, @records = pagy(:offset, scope, limit: 25)
```

For an independent table, name the metadata and page key explicitly:

```ruby
@arrivals_pagy, @bookings = pagy(
  :offset,
  scope,
  limit: 25,
  page_key: "arrival_page"
)
```

These examples define the planned interface. They are not implementation changes.

Keep authorization, hotel scoping, filtering, and ordering in the existing callers and queries. Pagination receives an already-scoped collection.

Keep existing page-parameter normalization where callers have it. Verify the installed version's behavior for missing, malformed, zero, and negative parameters before migrating other callers.

### 3. Establish the presenter contract

Later presenter migrations expose `paginated_rows` for records and `pagination` for the Pagy object.

Prefer controller-owned pagination when a presenter already receives a collection. Pass records and metadata into that presenter separately.

For presenters that construct arrays internally, use `Pagy::Method` with an explicit `request:` argument. Compute and memoize the pair once per presenter.

Do not use global request state. Query objects must not gain a dependency on HTTP requests just to generate navigation links.

Phase 1 verifies array support and explicit request context in focused tests. It does not migrate financial presenters or change their calculations.

### 4. Add the shared navigation component

Create `PanelsUI::Pagination < PanelsUI::BaseComponent`, following the existing component and stylesheet structure.

Proposed interface:

```erb
<%= render PanelsUI::Pagination.new(
  pagy: @pagy,
  aria_label: "Pagination",
  hide_when_single_page: false,
  link_data: { turbo_action: "advance" }
) %>
```

The `link_data` default is empty. Callers pass Turbo attributes only where their current navigation requires them.

The component owns:

- Desktop page numbers, gaps, and boundary controls.
- Mobile current-page and total-page display.
- Nova colors, spacing, borders, and responsive behavior through semantic tokens.
- Accessible link names, `aria-current`, disabled controls, and visible focus.
- Optional suppression for single-page and empty collections.

Default to rendering the single-page state. Callers that currently hide it pass `hide_when_single_page: true`.

Use Pagy's page-series support and `page_url` for page calculations and URLs. Use Rails tag helpers to escape attributes.

The installed 43.6.2 code exposes `series` as a protected method. The component isolates access through `send(:series, slots: 9)`.

Component tests cover this version-specific dependency. Page URLs use the public `page_url` helper.

Do not create links for unavailable previous or next pages. Use `app_icon` for icons, following `DESIGN.md`.

Use the Nova appearance only in `PanelsUI::Pagination`. Do not import Pagy's default stylesheet over the portal theme.

### 5. Preserve URL and Turbo behavior

Build links from the Pagy instance's request context. Preserve search terms, filters, tab selection, and other sections' page keys.

Use explicit request context or Pagy's supported URL options for canonical paths and caller-specific parameter changes.

Keep filter-reset behavior in the existing forms and controllers. The component must not decide which business filters to clear.

Apply `link_data` to the generated anchors. Preserve the current Turbo frame target and history action without adding a global navigation override.

Sources: [Pagy options](https://ddnexus.github.io/pagy/toolbox/configuration/options/), [offset options](https://ddnexus.github.io/pagy/toolbox/paginators/offset/), and [page URL helper](https://ddnexus.github.io/pagy/toolbox/helpers/page_url/).

### 6. Migrate one pilot page

Use the Admin API Keys index as the first integration. It has one relation, a 25-row limit, and one navigation control.

Replace its Kaminari call with Pagy and render the shared component. Use the Nova single-page state.

The pilot proves controller setup, metadata, navigation rendering, and request behavior. Array and multiple-page-key behavior receive focused tests without migrating financial pages.

Keep all seven Kaminari templates until the remaining pages migrate. Do not override the existing `paginate` helper or monkey-patch Active Record.

### Planned files

| File | Planned change |
|---|---|
| `Gemfile`, `Gemfile.lock` | Add Pagy while retaining Kaminari during migration |
| `config/initializers/pagy.rb` | Set shared defaults |
| `app/controllers/application_controller.rb` | Include `Pagy::Method` |
| `app/components/panels_ui/pagination.rb` | Define the component interface and presentation methods |
| `app/components/panels_ui/pagination/pagination.html.erb` | Render accessible navigation |
| `app/assets/tailwind/panel/pagination.css` | Apply compact Nova navigation with shared tokens |
| `app/assets/tailwind/application.css` | Import the pagination stylesheet |
| `app/controllers/admin/api_keys_controller.rb` | Apply Pagy to the pilot collection |
| `app/views/admin/api_keys/index.html.erb` | Render the shared component |
| `spec/components/panels_ui/pagination_spec.rb` | Cover navigation, states, URL parameters, and link attributes |
| `spec/requests/admin/api_keys_spec.rb` | Add or extend pilot request coverage |
| System Designs preview and registry | Show Pagy navigation in both themes and page-count states |

### Phase 1 completion checks

- The application boots with Pagy and Kaminari together.
- The pilot returns the correct first, second, last, and empty page records.
- Shared tests cover an array, explicit request context, and two independent page keys.
- Page-size request parameters cannot bypass caller limits.
- Links retain filters and caller-supplied Turbo attributes.
- Navigation renders correct labels, current-page state, gaps, and disabled boundaries.
- Existing Kaminari pages still render through the original helper and templates.
- Focused specs, scoped lint, the Tailwind build, and `git diff --check` pass.
- Human acceptance checks confirm the pilot's desktop, mobile, keyboard, and theme behavior.

Automated component tests inspect rendered HTML without browser automation. Record visual acceptance separately if it remains pending.

Phase 1 is complete when the foundation and pilot work. Removing Kaminari belongs to the final migration phase.

## Phase 1b: Pagy-only Nova redesign

Status: Implemented. Estimated effort: **0.5 working day**.

The redesign applies only to `PanelsUI::Pagination`. The seven Kaminari templates remain unchanged for direct comparison during migration.

The Pagy component uses semantic navigation, list, and item elements. Stable `data-slot` attributes identify its structural parts for component tests.

Available controls and page links use the shared ghost-button treatment. The current page uses a neutral border and a restrained shadow.

Controls use 32-pixel sizing and the established medium radius. Coarse-pointer devices receive the shared 40-pixel minimum target.

Desktop navigation retains First, Previous, Next, Last, page numbers, and gaps. Mobile navigation shows Previous, `Page X of Y`, and Next.

The System Designs preview shows multi-page and single-page states in both portal themes. Admin API Keys remains the real Pagy pilot.

## Performance expectations

No benchmark was run during this analysis. The source review does not prove that Kaminari causes the reported slowness.

Pagy can reduce pagination-library overhead. Standard offset pagination still uses a count query and an offset/limit query.

Large offsets, expensive queries, and full-dataset processing can remain slow after migration. See [Pagy offset documentation](https://ddnexus.github.io/pagy/toolbox/paginators/offset/).

Examples in this project:

- Folios load records and associations, construct rows, and filter them in Ruby before pagination.
- Payment presenters combine and sort payment records before pagination.
- Charge Register paginates a completed report result.
- Cashier Activity groups transactions before selecting the displayed page.

Replacing the array paginator does not remove the cost of preparing those arrays.

Later optimization options include:

| Method | Potential benefit | Behavior or implementation cost |
|---|---|---|
| `:offset` | Lower pagination-library overhead | Smallest behavior change; counts and large offsets remain |
| `:countish` | Reuses counts between page requests | Counts can become stale |
| `:countless` | Removes the total-count query | No exact total count; navigation limitations |
| `:keyset` | Avoids large offsets | Cursor navigation and suitable ordering/indexes |
| `:keynav_js` | Keyset pagination with numeric navigation | Client-side state; links beyond the highest visited page are unknown |

Sources: [pagination choices](https://ddnexus.github.io/pagy/guides/choose-right/), [countish](https://ddnexus.github.io/pagy/toolbox/paginators/countish/), and [keynav](https://ddnexus.github.io/pagy/toolbox/paginators/keynav_js/).

Logs and event streams are candidates for later keyset evaluation. Operational and financial screens retain offset pagination in the initial migration.

## Effort estimate

| Work | Estimated effort |
|---|---:|
| Pagy setup and shared pagination controls | 1–1.5 days |
| Pagy-only Nova redesign and preview | 0.5 day |
| Ordinary lists across the four portals | 1.5–2 days |
| Reports, financial presenters, and independent page controls | 1.5–2.5 days |
| Tests, fixes, and final checks | 1–2 days |
| **Total** | **5.5–8.5 working days** |

This is a planning estimate for one developer familiar with the project. It is not a measured execution time or delivery commitment.

Reports and financial pages carry the most uncertainty. Their totals, exports, filters, and separate page controls need careful regression checks.

A provisional budget for migration plus optimization of the slowest screens is **8–15 working days total**. Profiling must refine that estimate.

## Delivery and validation

1. Measure representative slow pages before implementation. Record database time, rendering time, query count, and memory allocations where practical.
2. Add Pagy and the shared navigation component. Preserve existing URL and page-size behavior.
3. Migrate ordinary lists, followed by presenters and report sections.
4. Remove Kaminari, its templates, and remaining dependency-specific calls after all consumers migrate.
5. Run focused regression tests and the repository's full `bin/ci` checks.
6. Compare representative performance measurements and complete acceptance checks.

Required regression cases include:

- First, middle, last, empty, and out-of-range pages.
- Missing, malformed, zero, and negative page parameters.
- Search and filter changes while viewing later pages.
- Independent pagination on screens with several sections.
- Stable ordering when records share the same sort value.
- Account and hotel access boundaries.
- Turbo response structure, links, and history attributes.
- Array pagination and presenter metadata.
- Report totals, statement balances, and full or selected exports.

Automated validation uses request tests, component rendering tests, and testable scripts. Browser automation is excluded by repository instructions.

Human acceptance checks cover desktop and mobile appearance, keyboard behavior, and light and dark themes. Passing automated tests alone does not establish visual acceptance.

## Completion criteria

- All Kaminari consumers use Pagy 43.6.x.
- Kaminari and its custom templates are removed.
- Migrated pages use the Nova pagination design, and page behavior remains unchanged.
- Filters, independent page keys, page sizes, and Turbo navigation remain correct.
- Report totals and exports retain their existing meaning.
- Required tests pass, and validation limits are recorded.
- Performance results distinguish gem overhead from database and report-processing costs.

## Current status

### Implemented

- Pagy 43.6.2 is installed alongside Kaminari. Bundler added its `yaml` dependency without upgrading existing gems.
- The initializer sets a 25-row default, disables client limit overrides, and freezes the options.
- `ApplicationController` includes `Pagy::Method`.
- `PanelsUI::Pagination` supplies shared server-rendered navigation and portal styling.
- Admin API Keys uses Pagy with a 25-row limit and stable `created_at DESC, id DESC` ordering.
- The pilot normalizes invalid page parameters and returns empty results for page overflow.
- All other pages retain Kaminari and its existing templates.
- Phase 1 is committed as `50e84293d`.
- Rubyzip 3.6.0 is committed separately as `eaa530716`.
- `PanelsUI::Pagination` uses the Pagy-only Nova design.
- System Designs shows the Pagy component in both themes and page-count states.

The Kaminari templates remain unchanged. Their appearance differs from Pagy during the staged migration by design.

### Validation

- Phase 1 focused specs: 16 examples, 0 failures.
- Phase 1 clean non-browser suite with `BULLET=true bin/test fast`: 8,319 examples, 0 failures.
- Phase 1 sequential migration checks: 45 examples across 18 files, 0 failures.
- Rubyzip 3.6.0 resolves the dependency version that blocked the earlier Bundle Audit run.
- Phase 1b component and request specs: 24 examples, 0 failures.
- Phase 1b scoped RuboCop: passed with no offenses.
- Phase 1b Tailwind build: passed.
- Phase 1b `git diff --check`: passed.
- The Kaminari template directory has no Phase 1b diff.
- The post-update default `bin/ci` run cleared RuboCop, Brakeman, Bundle Audit, Importmap Audit, Tailwind, and parallel database setup.
- Parallel RSpec ran 8,319 examples and reported three PostgreSQL deadlocks in unrelated report, invoice, and request-archive examples.
- A serial rerun of those exact examples passed: 3 examples, 0 failures.

An earlier broad run encountered two database deadlocks because migration checks ran concurrently against a shared test database. The clean sequential run passed.

Full CI is not green because the parallel test run reported three database deadlocks. No performance benchmark or browser automation was run.

### Remaining work

- Rerun default `bin/ci` or resolve the parallel database deadlocks separately.
- Complete human visual acceptance for desktop, mobile, keyboard behavior, and both themes.
- Migrate the remaining controllers, presenters, and reports in later phases.
- Remove Kaminari only after all consumers migrate.

Phase 1 and the rubyzip update are committed. The Phase 1b redesign is not committed. No database changes or deployment were made.
