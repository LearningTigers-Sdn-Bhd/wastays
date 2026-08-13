# Rate plans and rate inventory — technical handover

Last reviewed against the implementation on 2026-08-12.

This document describes the current rate-plan, Room Inventory, and Rates &
Availability behavior. It is a handover for engineers and product reviewers,
not a record of the deleted rate-plan wizard or tabbed editor.

## 1. Product model

The setup path now has two connected workspaces:

1. **Settings → Property → Room Inventory** owns room categories, room groups,
   reusable rate-plan assignments, and each assignment's standing price.
2. **Rates & Availability** owns date-specific prices, availability,
   restrictions, pricing rules, channel rows, and staged calendar updates.

A rate plan is hotel-scoped and reusable. The join model
`RoomTypeRatePlan` represents one rate plan attached to one room category and
owns the category-specific pricing rule or occupancy-price matrix.

The hotel owns the charging model:

- `per_room` — one room price, with included adults, an extra-adult charge,
  and a separate per-child charge;
- `per_person` — a total nightly room price for each supported adult count,
  plus the plan's child-pricing rules.

`RatePlan#inherit_sell_mode_from_hotel` copies the hotel value whenever a plan
is validated. `Hotel#mirror_sell_mode_to_rate_plans` mirrors a changed hotel
value onto existing plans.

## 2. Room Inventory

Room Inventory replaced the separate rate-settings registry. It is rendered by
the room-types index and presents room categories as an accordion. Each row
shows its room group, capacity, room count, rate issues, and actions. Expanding
a category shows its attached rate plans, standing prices, statuses, and
assignment actions.

The page supports:

- searching by room-category or rate-plan name;
- filtering by one or more room groups, including unassigned categories;
- creating and editing room categories;
- assigning room groups;
- creating/configuring one rate plan for one room category;
- assigning one reusable custom rate plan to several room categories;
- editing, detaching, archiving, restoring, or deleting plans where allowed.

Primary implementation:

```text
app/controllers/hotel_portal/room_types_controller.rb
app/queries/room_types_query.rb
app/views/hotel_portal/room_types/index.html.erb
app/views/hotel_portal/room_types/_inventory_room.html.erb
app/views/hotel_portal/room_types/_inventory_rate_plan.html.erb
```

## 3. Creating or configuring a rate plan

The old session-backed, multi-room wizard has been deleted. Its legacy routes
redirect to `rate_plans#new`.

The current **New rate** action opens a non-dismissible right-side sheet. The
sheet configures exactly one room category at a time:

1. Select a room category. Opening the sheet from an expanded category
   preselects it.
2. Search for an active custom rate plan or type a new name.
3. Enter shared plan details when creating a new plan.
4. Configure the selected category's standing price.
5. Save the plan and the selected assignment in one transaction.

An autocomplete selection is authoritative by id. Without an id,
`RatePlans::Resolve` normalizes the entered name and either reuses one matching
active custom plan or creates a new one. Ambiguous duplicate names are refused.
When an existing plan is selected, its shared details remain unchanged; the
sheet configures only the selected room's assignment.

`RatePlans::SaveRoomPricing` is the single persistence boundary for the
category-specific price. The controller suppresses per-assignment ARI callbacks
during the transaction, then requests one batched sync for the affected room.

Primary implementation:

```text
app/controllers/hotel_portal/rate_plans_controller.rb
app/forms/hotel_portal/rate_plan_room_pricing.rb
app/services/rate_plans/resolve.rb
app/services/rate_plans/save_room_pricing.rb
app/views/hotel_portal/rate_plans/_form_sheet.html.erb
app/views/hotel_portal/rate_plans/_room_pricing_fields.html.erb
app/javascript/controllers/rate_plan_editor_controller.js
app/javascript/controllers/rate_plan_room_pricing_controller.js
```

## 4. Assigning a reusable rate plan

The global **Assign → Assign Room Rate** action is deliberately narrower than
the New rate sheet. It chooses or creates one active custom rate plan and
attaches it to one or more room categories. It does not collect pricing.

`RatePlans::Attach` validates hotel ownership, resolves the plan once, skips
relationships that already exist, and creates all new assignments in one
transaction. It then batches channel synchronization for only the newly
attached categories.

`RatePlans::BootstrapAssignment` makes each new relationship immediately
usable:

- **Per room:** store a live 0% adjustment from that category's Standard Rate.
- **Per person:** copy the category's complete Standard Rate occupancy ladder.
  If an adult count is missing from Standard Rate, use
  `room_type.base_price × adults` for that count.

This bootstrap is a starting point, not shared cross-room pricing. Each room
category can be opened and priced independently afterwards.

Primary implementation:

```text
app/controllers/hotel_portal/rate_plan_attachments_controller.rb
app/forms/hotel_portal/rate_plan_attachment_form.rb
app/services/rate_plans/attach.rb
app/services/rate_plans/autocomplete.rb
app/services/rate_plans/bootstrap_assignment.rb
app/views/hotel_portal/rate_plan_attachments/new.html.erb
app/javascript/controllers/rate_plan_attachment_controller.js
```

## 5. Editing a rate plan

The deleted tabbed full-bottom sheet has been replaced by one right-side sheet
and one form.

The editor contains:

- a selector for the plan's attached room categories;
- read-only hotel charging model and currency context;
- shared plan details;
- pricing for the selected room category;
- shared child-pricing rules for per-person hotels;
- archive, restore, and delete actions where the plan permits them.

Saving updates the shared plan fields and the selected room's price in one
transaction. Switching the selected room reloads the pricing portion for that
assignment. Dirty-form guards protect room switches, closing, and destructive
actions.

Standard Rate uses the same shell, but its name and description cannot be
changed. For a per-room hotel its standing amount comes from the room
category's default nightly price; date-specific changes belong in Rates &
Availability. Per-person Standard Rate occupancy prices remain editable.

Detaching is handled separately by `RatePlans::RemoveRoomType`. It refuses to
remove the final category, refuses an assignment referenced by bookings, and
deletes a corresponding channel mapping after commit.

Primary implementation:

```text
app/controllers/concerns/rate_plan_editor_loading.rb
app/controllers/hotel_portal/rate_plans_controller.rb
app/controllers/hotel_portal/rate_plan_room_pricings_controller.rb
app/services/rate_plans/remove_room_type.rb
app/views/hotel_portal/rate_plans/_editor_sheet.html.erb
app/views/hotel_portal/rate_plans/_editor_details_fields.html.erb
```

## 6. Standing-price persistence

### Per-room hotels

`room_type_rate_plans.pricing_mode` and `pricing_value` store either:

- `fixed` plus a non-negative standing amount;
- `multiplier` plus a percentage adjustment from Standard Rate; or
- `offset` plus an amount adjustment from Standard Rate.

Multiplier and offset assignments remain live. A later Standard Rate change
changes their effective price unless a daily override exists.

### Per-person hotels

`room_type_rate_plan_occupancy_prices` stores one total nightly room price for
every adult count from 1 through the category's `max_adults`.

Manual entry must be complete. Derived and Auto are input helpers that generate
and materialize a complete matrix:

- **Derived:** apply the selected amount or percentage adjustment to every
  corresponding Standard Rate occupancy amount.
- **Auto:** use a typed anchor, then step across adult counts.

Generator provenance is not persisted. Reopening the plan shows editable direct
prices. Later Standard Rate changes do not update an already materialized
per-person matrix.

Child pricing is plan-wide. It supports one default child price and optional,
non-overlapping age bands with fixed or percentage pricing. The room category,
not the rate plan, owns child capacity.

## 7. Effective nightly-price resolution

`Rates::ResolveEffectiveNightlyPrice` is the local pricing authority used by
booking availability, stay pricing, financial snapshots, AI previews, and the
inventory calendar.

For the scalar room/adult anchor, current precedence is:

1. A requested walk-in or corporate tier value, when present on the selected
   or Standard daily row.
2. An explicit daily row for the selected room category and rate plan.
3. A fixed assignment's standing price.
4. A derived assignment applied to that date's Standard Rate.
5. A derived assignment applied to the room category's default nightly price
   when no Standard daily row exists.
6. Standard Rate or legacy unattributed daily data, then the room category's
   default nightly price.

For a per-person plan, the requested adult-count amount is resolved separately:

1. the selected daily row's occupancy override;
2. the assignment's stored occupancy price;
3. a derived amount from Standard Rate's daily or stored occupancy price.

Once any applicable occupancy matrix exists, a missing requested adult count
returns no price. It does not fall back to a scalar price.

After the adult/room amount is resolved, `Bookings::NightlyPaxPrice` applies
per-room extra-adult and per-child supplements or per-person child pricing. The one-guest
surcharge remains a legacy fallback only when no occupancy price supplied the
adult total.

## 8. Rates & Availability

The calendar renders availability and rate-plan rows for each visible room
category. It resolves displayed local prices through the same nightly resolver
used by bookings.

The grid supports one optional `room_type_id` and one optional `rate_plan_id`
for server-side scoping. The cell editor can then widen a staged change to a
date range, several room categories, and several rate plans.

Editing is staged:

1. Open one rate or availability cell.
2. Choose dates and targets, then change only the required fields.
3. Stage the update in the browser.
4. Review or remove pending changes.
5. Confirm once to persist the batch and enqueue channel synchronization.

Rate editing is charging-model-specific:

- Per-room local rates show room price, included adults, extra-adult charge,
  and per-child charge.
- Per-person local rates show one occupancy field per adult count for the
  clicked category. Child prices and age bands remain plan-wide.
- Channel overrides use the channel-compatible scalar controls.

The Advanced Pricing area continues to own pricing rules, availability
overrides, derived channel pricing, and channel availability rules.

Primary implementation:

```text
app/controllers/hotel_portal/inventory_dashboards_controller.rb
app/services/hotel_portal/inventory_calendar_presenter.rb
app/services/hotel_ops/apply_inventory_dashboard_selection.rb
app/views/hotel_portal/inventory_dashboards/_index_content.html.erb
app/views/hotel_portal/inventory_dashboards/edit_selection.html.erb
app/javascript/controllers/inventory_calendar_controller.js
```

## 9. Channel behavior

Channel eligibility is capability-based rather than sell-mode-wide.
`ChannelManagers::ChannexRatePlanCapability` accepts distributable per-room
plans and per-person assignments with a complete occupancy matrix. Per-person
age bands are flattened only when both Channex child and infant fees are set;
otherwise that plan remains unsupported. Scalar adult-rate export continues to
resolve adults with zero children, so the local per-child supplement does not
invent a new channel child-pricing contract. Rate-plan saves and new
attachments batch structure and ARI work for the affected room categories.

Special tier plans (`walk_in`, `corporate`, and `ota`) are internal price
anchors rather than guest-selectable offers. They cannot be archived or
deleted like custom plans.

## 10. Known gaps and risks

### Legacy partial occupancy matrices

New create/edit input requires a complete per-person matrix, and new
attachments bootstrap every supported adult count. Existing incomplete data is
not repaired automatically, however. Because the resolver refuses a missing
count once a matrix exists, affected inventory can disappear from availability.

Needed: an audit/backfill report and a deliberate policy for invalid legacy
rows. A database or model-level completeness guarantee would require accounting
for changes to `room_type.max_adults`.

### Charging-model transitions

`Hotel#mirror_sell_mode_to_rate_plans` uses `update_all`. It bypasses rate-plan
callbacks and does not reconcile occupancy matrices, scalar pricing fields,
age bands, daily occupancy overrides, or channel structures. Keep sell-mode
changes admin-only until an explicit transition service exists.

### Per-person distribution

Per-person distribution requires a complete adult occupancy matrix. Direct
age-band pricing is richer than Channex's child model, so age-banded plans are
distributed only through the explicit flattened child and infant fees described
above. Unsupported assignments remain local without blocking room-level
availability synchronization.

### Inventory setup guidance

There is no `Rates::SetupGaps` query, post-create calendar continuation, or
calendar nudge for missing coverage. Room Inventory can count assignment-level
pricing issues, but it does not audit future date coverage.

### Calendar filtering and price explanations

Server-side single-room/single-plan scoping exists, but there is no complete
multi-select view filter with removable chips. The presenter records each
resolved price's source, but the calendar does not yet expose a source legend
or an “explain this price” interaction.

### Multi-room per-person bulk editing

The cell editor sizes occupancy inputs to the clicked room category, fixing the
old hotel-wide maximum. If the user then selects categories with different
capacities, the editor still has one shared occupancy block rather than one
capacity-sized block per category.

## 11. Focused test coverage

Current behavior is primarily covered by:

```text
spec/requests/hotel_portal/rate_plans_spec.rb
spec/requests/hotel_portal/rate_plan_attachments_spec.rb
spec/requests/hotel_portal/room_types_spec.rb
spec/requests/hotel_portal/inventory_dashboards_spec.rb
spec/services/rate_plans/resolve_spec.rb
spec/services/rate_plans/attach_spec.rb
spec/services/rate_plans/bootstrap_assignment_spec.rb
spec/services/rate_plans/save_room_pricing_spec.rb
spec/services/rates/resolve_effective_nightly_price_spec.rb
spec/services/hotel_portal/inventory_calendar_presenter_spec.rb
spec/system/hotel/inventory_workspace_spec.rb
spec/system/hotel/inventory_tabs_spec.rb
```
