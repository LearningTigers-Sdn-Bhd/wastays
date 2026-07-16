# Hotel Stay View Refactor

## Status

- Branch: `refactor/room-gantt-chart`
- Document type: architecture and implementation contract
- Scope: Hotel portal Stay View
- Legacy sources being replaced:
  - Booking Timeline — Stay View
  - Booking Timeline — Room View
  - Room Status Board

## Objective

Build a new Hotel Stay View that combines reservation planning and room operations without depending on either legacy board's projection logic, presenters, helpers, partials, controllers, or JavaScript.

The new feature will provide two presentation modes over one shared data projection:

1. **Timeline View** — a multi-day room Gantt/tape chart for planning stays and dated room operations.
2. **Room View** — a one-day operational card view for front desk and housekeeping work.

The implementation must reuse authoritative domain models, authorization rules, booking command services, PanelsUI primitives, and semantic portal theme tokens. It must not create a competing booking engine or duplicate mutation rules.

## Core decisions

1. The new Stay View is isolated from both legacy boards.
2. Timeline View and Room View use the same query, projection, permissions, and action services.
3. Booking occupancy uses half-open date ranges: check-in is inclusive and checkout is exclusive.
4. Timeline booking bars run from the centre of the check-in day to the centre of the checkout day.
5. Physical room status and booking occupancy are separate dimensions.
6. Current mutable room status is not projected across historical or future dates.
7. PanelsUI owns reusable timeline structure and interaction styling.
8. Stay View components own hotel-specific meaning and booking actions.
9. The server-rendered projection is the source of truth.
10. Stimulus enhances interaction but does not implement booking business rules.
11. Turbo navigates and refreshes meaningful board regions without thousands of nested frames.
12. Every drag or resize workflow has an explicit keyboard- and touch-friendly action alternative.
13. Every action is authorized by the server even when its control is omitted from the UI.

## Legacy boundary

The new Stay View must not reference or copy logic from:

- `Rooms::ReservationBoardBuilder`
- `Rooms::RoomStatusBoardBuilder`
- `HotelPortal::BookingTimelineBoardPresenter`
- `HotelPortal::RoomStatusBoardPresenter`
- `HotelPortal::BookingTimelineBoardHelper`
- Legacy room status board helpers
- Legacy booking timeline partials
- Legacy room status board partials
- `booking_timeline_controller.js`
- Legacy board controller parsing or filtering methods

The legacy boards remain available during development and parity validation. They should not be modified to serve the new view, and they should not be deleted in the initial implementation.

The new feature may and should reuse:

- Existing hotel, room type, booking, booking room, room status, room block, rate, and housekeeping models
- Existing booking and room-operation command services that are authoritative for mutations
- Existing Pundit policies and permission infrastructure
- Existing PanelsUI controls, sheets, menus, badges, and semantic styling
- Existing portal shell and `panel-page` layout ownership
- Existing Turbo off-canvas infrastructure where its API is appropriate

## Feature comparison

| Feature | Legacy Timeline — Stay | Legacy Timeline — Room | Legacy Room Status | New Timeline View | New Room View |
|---|---|---|---|---|---|
| Primary purpose | Reservation planning | One-day room availability | Room readiness operations | Combined stay and operations planning | One-day room operations |
| Layout | Multi-day Gantt | Room cards | Multi-day status grid | Multi-day centre-aligned Gantt | Responsive room cards |
| Date range | 7, 14, 21, 30 days | 1 day | 7, 14, 21 days | 7, 14, 21, 30 days | 1 selected day |
| Shared data model | No | Partially | No | Yes | Yes |
| Booking bars | Yes | No | Limited | Yes | Booking summary cards |
| Physical room status | Simplified not-ready state | Simplified not-ready state | Detailed current status | Current status plus dated blocks | Detailed current status |
| Booking occupancy | Yes | Yes | Separate resolver | Yes | Yes |
| Maintenance blocks | Partial | Partial | Yes | Yes | Yes for selected day |
| Housekeeping alerts | No | No | Yes | Yes | Yes |
| DND and priority | No | No | Yes | Yes | Yes |
| Add booking | Empty timeline cell | Available room card | No | Empty timeline cell | Available room card |
| Move booking | Mouse drag | No | No | Explicit action and optional drag | Explicit action |
| Change dates | Mouse resize | No | No | Explicit action and optional resize | Explicit action |
| Change room status | No | No | Yes | Yes | Yes |
| Permission granularity | Broad | Broad | Separate | Capability-based | Capability-based |
| Keyboard alternative | Incomplete | Partial | Partial | Required | Required |
| Touch operation | Weak | Better | Partial | Action-first | Action-first |
| URL-backed state | Partial | Partial | Partial | Complete | Complete |
| Semantic theme compliance | Inconsistent | Inconsistent | Inconsistent | Required | Required |

## View modes

### Timeline View

Timeline View is the planning workspace. It displays rooms as rows and dates as columns.

It includes:

- Sticky room column
- Sticky date header
- Room grouping by room type
- Collapsible room-type groups
- Centre-of-day booking bars
- Arrival and departure edges
- Booking status and guest identity
- Maintenance and out-of-service blocks
- Current physical room status
- Housekeeping, DND, and priority alerts
- Available date-cell actions
- Room rates when permitted and requested
- Move Stay and Change Dates actions
- Optional pointer drag and resize enhancement
- Filters for room type, booking status, occupancy, physical status, and rate plan

### Room View

Room View is the one-day operational workspace. It renders the same projection as responsive room cards.

It includes:

- Selected operational date
- Room number and room type
- Current physical status
- Arrival, occupied, departure, or available state
- Guest and booking summary
- Checkout countdown or overdue warning
- Housekeeping requests
- DND and priority flags
- Smoking and pet attributes
- Add Booking, Walk-in, and permitted backdated actions
- Booking lifecycle actions
- Room-status actions
- Room-block actions

### View switching

Use `PanelsUI::Tabs` with the `line` variant. The selected view must be URL-backed and bookmarkable.

Example URLs:

```text
/hotel/:hotel_id/stay-view?view=timeline&start_date=2026-07-16&days=14
/hotel/:hotel_id/stay-view?view=rooms&date=2026-07-16
```

Switching views replaces the primary Stay View Turbo Frame and uses `data-turbo-action="advance"` so browser history, refresh, and shared links preserve state.

## Architecture

```text
Authoritative domain models and commands
                  |
                  v
          StayView query services
                  |
                  v
        StayView projection services
                  |
                  v
       Immutable StayView view models
                  |
          +-------+-------+
          |               |
          v               v
 PanelsUI timeline    StayView domain
    primitives          components
          |               |
          +-------+-------+
                  |
                  v
       Server-rendered HTML/Turbo
                  |
                  v
       Stimulus interaction layer
```

## Proposed file structure

```text
app/
├── controllers/hotel_portal/stay_view/
│   ├── board_controller.rb
│   ├── booking_moves_controller.rb
│   ├── booking_dates_controller.rb
│   └── room_operations_controller.rb
├── services/stay_view/
│   ├── build_board.rb
│   ├── load_inventory.rb
│   ├── project_room.rb
│   ├── project_booking.rb
│   ├── resolve_occupancy.rb
│   ├── resolve_current_room_status.rb
│   └── calculate_counts.rb
├── models/stay_view/
│   ├── board.rb
│   ├── date_window.rb
│   ├── room_group.rb
│   ├── room_row.rb
│   ├── day_cell.rb
│   ├── booking_segment.rb
│   ├── operational_segment.rb
│   └── capabilities.rb
├── components/panels_ui/timeline/
│   ├── table.rb
│   ├── header.rb
│   ├── group.rb
│   ├── row.rb
│   ├── cell.rb
│   └── segment.rb
├── components/hotel_portal/stay_view/
│   ├── board.rb
│   ├── timeline_view.rb
│   ├── room_view.rb
│   ├── toolbar.rb
│   ├── legend.rb
│   ├── room_summary.rb
│   ├── booking_bar.rb
│   ├── operational_bar.rb
│   └── cell_actions.rb
├── helpers/hotel_portal/
│   └── stay_view_helper.rb
├── javascript/controllers/stay_view/
│   ├── viewport_controller.js
│   ├── interaction_controller.js
│   ├── filters_controller.js
│   └── scroll_state_controller.js
└── views/hotel_portal/stay_view/
    ├── board/index.html.erb
    └── streams/
```

The final names may be adjusted to repository conventions, but the namespace and dependency boundary must remain clear.

## Service responsibilities

### `StayView::DateWindow`

Owns:

- Hotel-local current date
- Hotel business date when operationally relevant
- Start and exclusive end dates
- Allowed range sizes
- Previous and next ranges
- Date clipping
- Date-to-track conversion
- URL parameter parsing and validation

No view or controller should calculate date boundaries independently.

### `StayView::LoadInventory`

Loads all records required for the selected hotel and date window in a bounded number of queries:

- Room types and configured room numbers
- Overlapping bookings and booking rooms
- Current room statuses
- Active room blocks
- Relevant housekeeping flags
- Rates only when enabled and permitted

It must prevent N+1 queries and avoid loading folios, full histories, notes, or guest records that the board does not render.

### `StayView::BuildBoard`

Coordinates loading and projection. It returns a `StayView::Board`, not a hash containing Active Record objects.

### `StayView::ProjectRoom`

Builds one immutable room row from preloaded records. It does not execute additional queries.

### `StayView::ProjectBooking`

Creates clipped, presentation-ready booking segments using the shared date contract.

### `StayView::ResolveOccupancy`

Resolves only dated booking occupancy:

- Available
- Arrival
- Occupied
- Departure

It does not resolve physical readiness.

### `StayView::ResolveCurrentRoomStatus`

Resolves the current physical condition:

- Ready
- Dirty
- Cleaning
- Awaiting inspection
- Inspection failed
- Out of service

It does not project the mutable current status across past or future dates.

### `StayView::CalculateCounts`

Calculates legends and summaries after all selected filters are applied. All visible counts must describe the same final projection.

## View model contract

View models should be immutable, presentation-ready Ruby objects. Components must not query or derive business state.

### Board

```ruby
StayView::Board
  .view_mode
  .date_window
  .room_groups
  .status_counts
  .filters
  .capabilities
  .empty?
```

### Room row

```ruby
StayView::RoomRow
  .key
  .dom_id
  .room_number
  .room_type
  .current_physical_status
  .occupancy_for(date)
  .operational_flags
  .day_cells
  .booking_segments
  .operational_segments
  .capabilities
```

### Booking segment

```ruby
StayView::BookingSegment
  .dom_id
  .booking_id
  .guest_label
  .status
  .check_in
  .check_out
  .start_track
  .end_track
  .clipped_left?
  .clipped_right?
  .accessible_label
  .capabilities
```

### Operational segment

```ruby
StayView::OperationalSegment
  .dom_id
  .kind
  .label
  .start_date
  .end_date
  .start_track
  .end_track
  .accessible_label
  .capabilities
```

## Date and occupancy contract

Booking occupancy must use a half-open interval:

```ruby
check_in <= occupied_date && occupied_date < check_out
```

Consequences:

- Check-in is inclusive.
- Checkout is exclusive.
- A 16–17 July booking occupies one night.
- A departing booking and arriving booking can share the same room on the turnover date.
- The checkout date is a departure event, not an occupied night.
- Clipping never changes the underlying stay duration.
- Every service, component, filter, count, and test uses the same rule.

Booking overlap queries must use:

```sql
check_in < window_end AND check_out > window_start
```

The hotel timezone or business date determines today. Server `Date.current` must not independently drive board rendering.

## Centre-of-day timeline geometry

Each day is represented by two equal tracks:

```text
| morning | afternoon | morning | afternoon |
                    [ booking              ]
                      check-in      checkout
```

Rules:

- Booking bars begin at the centre of the check-in day.
- Booking bars end at the centre of the checkout day.
- One-night stays connect the centres of adjacent dates.
- Arrival and departure edges may use distinct markers.
- Maintenance and out-of-service segments fill complete operational days.
- A segment continuing from outside the visible range attaches to the relevant board edge.
- Clipped edges must have a visible continuation treatment and accessible wording.

PanelsUI owns the track geometry. Stay View components supply semantic start and end tracks. Pages and helpers must not calculate pixel widths.

Initial layout must use CSS Grid rather than JavaScript measurements. Stimulus may read geometry only during an active pointer interaction.

## Physical status and occupancy separation

Physical condition and booking occupancy are independent:

| Physical condition | Booking occupancy |
|---|---|
| Ready | Available |
| Dirty | Arrival |
| Cleaning | Occupied |
| Awaiting inspection | Departure |
| Inspection failed | — |
| Out of service | — |

A room can therefore be both `dirty` and `arrival`, or `ready` and `occupied`, depending on operational state and booking lifecycle.

The current persisted `RoomStatus` belongs in the sticky room summary and, when appropriate, today's cell. It must not be shown as if it were the room's status for every past and future date.

Dated state comes from:

- Bookings for occupancy
- Room blocks for maintenance and out-of-service periods
- A future dated room-status interval model if historical physical-state reconstruction is required

Operational audit logs should not be treated as complete status intervals unless a tested reconstruction service is introduced.

## Component architecture

### PanelsUI timeline primitives

PanelsUI owns reusable presentation and interaction foundations:

- Timeline viewport
- Sticky room column
- Sticky date header
- Timeline groups, rows, and cells
- Half-day grid tracks
- Generic segments
- Clipped and continuation edges
- Compact and comfortable density
- Horizontal overflow
- Focus and hover treatment
- Semantic borders, radii, and surfaces
- Light and dark theme behaviour

PanelsUI timeline primitives must not know about:

- Guests
- Booking lifecycle states
- Check-in or checkout commands
- Hotel permissions
- Housekeeping workflow
- Rate plans

### Stay View domain components

Stay View owns hotel meaning:

- Booking bars
- Operational blocks
- Room summaries
- Occupancy indicators
- Room-status badges
- Housekeeping, DND, and priority alerts
- Available cell actions
- Permission-aware action menus
- Timeline and Room View composition

### Helpers

`HotelPortal::StayViewHelper` must remain small and pure. Appropriate responsibilities include:

- Locale-aware date labels
- Currency display through existing formatting infrastructure
- Stable DOM IDs when a component cannot own them
- Plain text accessibility labels assembled from view-model data

Helpers must not:

- Query models
- Resolve availability
- Resolve permissions
- Map business status to page-local palette utilities
- Calculate timeline geometry
- Mutate view models

## Semantic theme contract

The new view must use portal semantic tokens and existing PanelsUI treatments.

Examples:

| Purpose | Semantic treatment |
|---|---|
| Page background | `background` |
| Timeline surface | `card` / `card-foreground` |
| Secondary surface | `muted` / `muted-foreground` |
| Grid boundaries | `border` |
| Interactive boundaries | `border-interactive` |
| Primary action | `primary` / `primary-foreground` |
| Keyboard focus | PanelsUI focus treatment |
| Booking state | Established semantic status tokens |
| Blocked/destructive state | Established destructive status tokens |

Components receive semantic states:

```ruby
BookingBar.new(status: :checked_in)
OperationalBar.new(status: :cleaning)
RoomStatusBadge.new(status: :inspection_failed)
```

Pages must not supply palette utilities such as `blue-*`, `red-*`, `green-*`, `purple-*`, `slate-*`, or arbitrary colors. They must not introduce local font scales, arbitrary spacing, decorative uppercase text, or `font-black` typography.

The timeline geometry is independent of theme styling and must work in both light and dark portal themes.

## Permission model

The projection should calculate explicit capabilities for the current hotel and user:

```ruby
StayView::Capabilities
  .view_board?
  .view_booking?
  .create_booking?
  .move_booking?
  .change_dates?
  .reassign_room?
  .check_in?
  .check_out?
  .view_rates?
  .view_financial_status?
  .view_room_readiness?
  .manage_room_status?
  .manage_housekeeping?
  .manage_room_blocks?
```

Expected behaviour:

| Capability | UI result |
|---|---|
| View board only | Read-only rooms and non-sensitive booking summaries |
| View booking | Booking link or details action |
| Create booking | Available-cell booking actions |
| Move booking | Move action and optional drag handle |
| Change dates | Change Dates action and optional resize handle |
| Manage room status | Readiness actions |
| Manage housekeeping | Housekeeping requests and task actions |
| Manage room blocks | Block Room and maintenance actions |
| View rates | Rate layer and rate-plan filter |
| View financial state | Permitted payment warnings or balances |

Unauthorized controls should normally be omitted rather than visually disabled. Sensitive values must not be embedded in HTML or data attributes when permission is absent.

Every mutation controller or command authorizes again on the server. UI capability checks are not an authorization boundary.

## Controller responsibilities

### Board controller

`HotelPortal::StayView::BoardController#index` should:

1. Authorize board access.
2. Parse URL-backed filters through a dedicated parameter object or `DateWindow`.
3. Build current-user capabilities.
4. Call `StayView::BuildBoard`.
5. Render the selected mode.

It must not load individual associations, calculate status, build CSS classes, or mutate booking state.

### Mutation controllers

Use focused controllers for proposed changes:

- Booking moves
- Booking date changes
- Room reassignment where separate from moving
- Room operational status changes
- Room blocks

Each controller should:

1. Load and authorize the relevant resource.
2. Render a confirmation form for a proposal.
3. Validate authoritative availability on submission.
4. Invoke the existing domain command service.
5. Respond with Turbo Stream and HTML fallbacks.
6. Return actionable validation errors with `422 Unprocessable Entity`.

Do not perform booking mutations directly inside Stimulus or a visual component.

## Turbo architecture

### Primary frame

Use one coarse board frame:

```erb
<%= turbo_frame_tag "stay_view_board", data: { turbo_action: "advance" } do %>
  ...
<% end %>
```

The following actions replace this frame while advancing browser history:

- View switching
- Date navigation
- Date-range changes
- Room-type filtering
- Status filtering
- Occupancy filtering
- Rate-plan filtering
- Density changes

Do not create one Turbo Frame per timeline cell. This would produce excessive nesting and fragile updates.

### Action frame

Use a dedicated frame or the established PanelsUI off-canvas frame for action sheets:

- Open booking
- Move Stay
- Change Dates
- Reassign Room
- Change Room Status
- Create Housekeeping Request
- Block Room

### Mutation response

The initial correctness-first implementation may replace the complete `stay_view_board` frame after a mutation.

Once stable, Turbo Stream responses may replace:

- Affected room rows
- Status and occupancy counts
- Flash/notification region
- Open action sheet

All affected rows must be rebuilt through the same Stay View projection services. Mutation responses must not assemble partial state independently.

### Real-time updates

Do not broadcast permission-sensitive rendered booking HTML from model callbacks.

If live multi-user refresh is introduced:

1. Broadcast a hotel-scoped invalidation signal.
2. Let each connected client refresh its permission-aware board frame.
3. Debounce repeated invalidations.
4. Preserve scroll and focus.
5. Avoid refreshing while the user is confirming an action without warning.

Real-time broadcasting is a later phase, not a prerequisite for the initial board.

## Stimulus architecture

Stimulus enhances the server-rendered board. It must not become a client-side source of truth.

### `stay-view--viewport`

Responsibilities:

- Scroll to today on initial load when appropriate
- Synchronize sticky header behaviour
- Preserve horizontal and vertical scroll across Turbo replacement
- Restore a focused booking or room when possible

### `stay-view--interaction`

Responsibilities:

- Begin and end pointer drag proposals
- Begin and end pointer resize proposals
- Highlight valid drop targets
- Convert a selected track into proposal parameters
- Open the server-rendered confirmation sheet
- Cancel visual proposals cleanly

It must not:

- Update booking records
- Decide authoritative availability
- Construct routes from `window.location`
- Duplicate hotel date rules
- Render booking HTML

Endpoints and identifiers should be passed through Stimulus values.

### `stay-view--filters`

Responsibilities:

- Submit filters through the board frame
- Debounce only inputs that benefit from it
- Preserve explicit URL state
- Avoid duplicate submissions

### Controller lifecycle

Every Stimulus controller must:

- Use declared targets, typed values, and actions
- Clean up document/window listeners in `disconnect()`
- Clean up timers and observers
- Tolerate Turbo disconnect/reconnect cycles
- Avoid duplicate event registration
- Keep animations interruptible
- Respect reduced-motion preferences

An `AbortController` or equivalent cleanup strategy is recommended for temporary global pointer listeners.

## Interaction design

### Booking interaction

Clicking or focusing a booking bar exposes permitted actions:

- Open Booking
- Move Stay
- Change Dates
- Reassign Room
- Check In
- Check Out
- Mark No Show
- Cancel Booking

The exact actions depend on capabilities and booking lifecycle.

### Drag and resize

Drag and resize are optional accelerators for pointer users.

Flow:

1. User begins dragging or resizing.
2. Stimulus displays a visual proposal.
3. Dropping opens a confirmation sheet.
4. Server reloads authoritative state and validates the proposal.
5. User confirms.
6. Existing booking command performs the mutation.
7. Turbo refreshes the affected board content.

Dropping never mutates a booking immediately.

### Non-drag alternatives

Every movable or resizable booking must provide:

- **Move Stay** — room and check-in selection
- **Change Dates** — check-in and checkout selection
- **Reassign Room** — when this is a distinct workflow

These actions are the primary accessible and mobile workflows. Dragging is progressive enhancement.

## Accessibility requirements

The new Stay View must meet WCAG 2.2 AA and the repository UI contract.

Required behaviour:

- Semantic page and section headings
- Accessible date and room headers
- Booking controls with guest, status, room, and complete date labels
- Visible status text or icons in addition to color
- Keyboard access to every action
- Visible focus using PanelsUI treatments
- Focus restoration after sheets close
- `aria-live="polite"` feedback for asynchronous success and relevant errors
- Reduced-motion support
- Minimum pointer target sizing
- Logical DOM and reading order
- Long guest and room-type name handling
- Zoom, reflow, and mobile keyboard support
- Decorative icons hidden from assistive technology
- Actionable validation error messages

Avoid `role="grid"` unless complete grid keyboard behaviour is implemented. Prefer semantic table structure where practical, with booking overlays represented by native links or buttons.

## URL and filter contract

Board state must be represented in query parameters.

Timeline example:

```text
?view=timeline
&start_date=2026-07-16
&days=14
&room_type_id=12
&booking_status=checked_in
&occupancy=occupied
&physical_status=ready
&rate_plan_id=8
&density=comfortable
```

Room View example:

```text
?view=rooms
&date=2026-07-16
&room_type_id=12
&occupancy=departure
&physical_status=dirty
```

Rules:

- Unknown values fall back safely.
- Dates are parsed through `DateWindow`.
- Range sizes are allow-listed.
- Hidden or unauthorized filters are ignored server-side.
- Switching views preserves compatible filters.
- Refresh, sharing, browser back, and browser forward retain state.

## Empty, loading, and error states

The board must explicitly handle:

- No room types configured
- Room type with no room numbers
- No bookings in the selected range
- No rooms matching filters
- No rate plan or unavailable rates
- Failed frame request
- Booking conflict after a proposal
- Room made unavailable by another user
- Permission changed while the page was open
- Booking or room removed before confirmation

Empty states should explain the next appropriate action without presenting broken grid geometry.

## Performance requirements

`StayView::LoadInventory` should use a bounded query set and eager loading.

Expected query groups:

1. Room types and room numbers
2. Overlapping bookings and booking rooms
3. Current room statuses
4. Active room blocks
5. Relevant housekeeping flags
6. Rates only when enabled and authorized

Requirements:

- No N+1 queries
- Maximum 30 visible days initially
- Query count remains stable as room count grows
- No layout measurement during initial JavaScript render
- No full booking histories or folios without explicit need
- Rates and sensitive financial data are not loaded without permission
- Instrument service duration, render duration, row count, and segment count

Before adding indexes, inspect current indexes and query plans. Likely access paths include:

- Bookings by hotel, status, check-in, and checkout
- Booking rooms by booking, room type, and room number
- Room statuses by hotel, room type, and room number
- Room blocks by hotel, room, start date, end date, and completion state

Database migrations should only be added when verified query plans demonstrate the need.

## Testing strategy

### Service specs

- One-night stay
- Same-day room turnover
- Check-in inclusive and checkout exclusive
- Booking clipped on the left
- Booking clipped on the right
- Booking spanning the complete window
- Hotel timezone boundary
- Hotel business date boundary
- Multi-room booking
- Multiple sequential bookings in one room
- Maintenance overlap
- Current physical status shown only as current state
- Filter combinations
- Counts calculated after filters
- Permission capabilities
- Stable query count

### Component specs

- Semantic status tokens
- No palette utilities
- Correct heading and typography roles
- Booking accessible label
- Operational block accessible label
- Centre-of-day start and end tracks
- Continuation edges
- View-only booking link
- Editable booking actions
- Unauthorized actions omitted
- Long guest and room-type names
- Empty room row
- Light and dark compatible markup

### Request specs

- Authentication
- Board authorization
- Each relevant permission boundary
- Timeline and Room View rendering
- URL parsing and safe fallbacks
- Turbo Frame response
- HTML response
- Successful Turbo Stream mutation
- HTML mutation fallback
- Invalid proposal returns `422`
- Conflicting booking move
- Unauthorized mutation
- Sensitive data excluded without permission

### System specs

- Switch between Timeline and Room View
- Browser back and forward restore view state
- Open booking with keyboard
- Complete Move Stay without dragging
- Complete Change Dates without resizing
- Drag creates a proposal and requires confirmation
- Resize creates a proposal and requires confirmation
- Cancel proposal without mutation
- Focus restored after closing a sheet
- Scroll preserved after Turbo update
- Room-status change updates the board
- Housekeeping action updates alerts
- No duplicate Stimulus listeners after repeated Turbo navigation
- Relevant mobile/touch workflow

Core lifecycle examples must not remain skipped or pending.

## Delivery phases

### Phase 1 — Contracts and read-only projection

- Establish date, occupancy, status, and permission contracts
- Create isolated Stay View namespace
- Build `DateWindow`, loader, projection services, and view models
- Add service specs

### Phase 2 — PanelsUI timeline foundation

- Audit existing PanelsUI primitives
- Add only missing reusable timeline primitives
- Implement semantic theme and density behaviour
- Add component specs and real Stay View usage

### Phase 3 — Read-only views

- Add the Stay View route and board controller
- Implement Timeline View
- Implement Room View
- Add URL-backed view switching, dates, and filters
- Validate desktop, mobile, light, and dark themes

### Phase 4 — Turbo actions

- Add booking and room action sheets
- Integrate authoritative domain commands
- Add whole-board Turbo refresh after mutations
- Add HTML fallbacks and request specs

### Phase 5 — Enhanced interactions

- Add pointer drag proposals
- Add pointer resize proposals
- Add scroll and focus preservation
- Replace affected rows rather than the complete board where justified
- Add system specs

### Phase 6 — Operational parity

- Add housekeeping alerts and actions
- Add DND and priority indicators
- Add room blocks
- Add permission-gated rates and financial signals
- Validate parity against both legacy boards

### Phase 7 — Adoption

- Point hotel navigation to Stay View
- Monitor errors, performance, and operational feedback
- Retain legacy routes for a defined fallback period
- Remove legacy boards in a separate cleanup branch after acceptance

### Phase 8 — Optional live invalidation

- Add hotel-scoped Turbo Stream subscription
- Broadcast invalidation rather than permission-specific HTML
- Debounce refreshes
- Preserve interaction state
- Add multi-session system coverage where practical

## Acceptance criteria

The refactor is ready to replace the legacy boards when:

- Timeline View and Room View use one shared projection.
- No new Stay View code references legacy board logic or helpers.
- Booking bars align centre-to-centre across check-in and checkout dates.
- Booking occupancy is consistent and checkout-exclusive everywhere.
- Physical status and occupancy remain visually and logically distinct.
- Current room status is not falsely projected across dates.
- Filters and legend counts describe the same visible rows.
- View switching and filters are URL-backed.
- Semantic theme tokens are used without portal palette utilities.
- Permissions control data loading, rendering, and server mutations.
- Every drag or resize action has a complete non-drag alternative.
- Turbo updates preserve relevant scroll and focus state.
- Stimulus controllers clean up correctly across Turbo navigation.
- No N+1 queries are introduced.
- Core service, component, request, and system tests pass without skips.
- Desktop, mobile, light, dark, keyboard, and long-content states are verified.
- The existing authoritative booking and room-operation commands remain the mutation source of truth.

## Risks and mitigations

| Risk | Mitigation |
|---|---|
| Recreating conflicting booking rules | Reuse authoritative mutation commands and centralize date semantics |
| Current room status shown as historical truth | Keep it in current room summary/today; use dated blocks for future state |
| Permission-sensitive data leaked through HTML | Capability-aware loading and server-side authorization |
| Drag interaction excludes keyboard or touch | Make explicit action sheets primary; drag is enhancement |
| Turbo updates disrupt scroll or focus | Dedicated viewport controller and focused replacement strategy |
| Real-time rendered HTML ignores user permissions | Broadcast invalidation, then reload permission-aware frames |
| Timeline becomes a generic component with hotel logic | Keep PanelsUI geometry generic and Stay View components domain-specific |
| Large hotel produces excessive DOM | Bound date range, instrument rendering, collapse groups, optimize only from evidence |
| New and legacy boards diverge during rollout | Freeze legacy feature development and validate parity before redirecting navigation |

## Non-goals for the initial implementation

- Rewriting booking lifecycle services
- Rewriting room-status mutation services
- Deleting legacy boards in the same implementation phase
- Building a client-side booking store
- Immediate booking mutation on drag/drop
- Pixel-perfect time-of-day placement based on check-in hours
- Reconstructing historical physical room status without an explicit interval model
- Real-time Action Cable broadcasting before the normal Turbo workflow is stable

## Future options

After the fixed centre-of-day implementation is stable, the track model may support actual hotel times. For example, a 15:00 check-in could begin at 62.5% of the arrival day and a 12:00 checkout could end at 50% of the departure day.

Other future options include:

- Historical physical-status intervals
- Configurable operational overlays
- Occupancy and readiness summary metrics
- Room comparison or focused-room mode
- Print/export view
- Live multi-user invalidation
- Large-property rendering optimization based on measured thresholds

These options must preserve the same service, permission, semantic theme, and accessibility boundaries.
