# AI Concierge V3 Research

## Goal

Build `AiConciergeV3` as a hybrid workflow where:

- LLM handles structured interpretation only
- Ruby handles state, transitions, validation, tool execution, side effects, and guest-facing reply rendering

## Key Product Decisions

1. `2 people` must trigger a clarification question
2. `adults` after `2 people` means `2 adults, 0 children`
3. selecting an option requires confirmation before generating the booking link
4. completed booking branches live only in short-lived conversation state
5. the final booking reply should include:
   - booking URL
   - total amount
   - expiry
6. month-window booking requests require duration before search
7. guest-facing replies are deterministic, not model-generated

## Core Architecture Direction

### AI responsibilities

- interpret the user's message into structured meaning
- return slots, intent, and conversation signals only

### Ruby responsibilities

- load and persist conversation state
- manage booking branches
- validate legal transitions
- decide which tools may run
- execute tools
- invalidate stale suggestion sets
- guard against invented timing, duration, and guest-count splits
- preserve disambiguation context across turns
- render deterministic guest-facing replies
- generate booking links through the existing quote flow

## Target Workflow

1. user sends message
2. `InterpreterAgent` returns structured interpretation
3. `TurnOrchestrator` applies deterministic guards to timing, duration, and guest count
4. orchestrator merges safe slots into state and decides the next action
5. orchestrator executes one or more deterministic tools
6. orchestrator builds structured reply context
7. `MessengerAgent` renders `reply_message`
8. Ruby returns public payload and persists state updates

## Booking State Requirements

The active booking branch must preserve enough data to survive:

- missing-slot follow-up
- option selection
- confirmation
- hotel-policy interruption
- correction from one month window to another
- a second booking started in the same conversation
- multi-turn ambiguity resolution across date, room type, and option number

Recommended active payload shape:

```json
{
  "branch_id": "uuid",
  "target_month": 8,
  "target_year": 2026,
  "month_segment": "late",
  "check_in": null,
  "check_out": null,
  "nights": null,
  "days": null,
  "room_count": 1,
  "party_size_total": 2,
  "adults": null,
  "children": null,
  "clarification_needed": null,
  "suggested_options": [],
  "suggestion_set_version": 1,
  "pending_selection": null,
  "confirmation_candidate": null,
  "selected_option": null
}
```

`pending_selection` is used to preserve ambiguity context such as:

```json
{
  "check_in": "2026-05-21",
  "room_type_name": "Ocean Villa King",
  "candidate_room_type_names": ["Ocean Villa King", "Executive Penthouse"]
}
```

Paused booking flows must retain:

- pending question
- suggestion set
- active booking slots
- expiry timestamp

Completed booking branches should remain only in short-lived conversation state.

## Required Conversation Behaviors

### Timing and duration

- `booking for 2 adults`
- ask: what dates or month?
- `early august`
- ask: how many days and nights?
- `3 days 2 nights`
- continue to guest-count or guest-split step

### Guest clarification

- `early june for 2 people`
- ask: how many days and nights?
- `2 days 1 night`
- ask: for 2 people, how many are adults and how many are children?
- `2 adults`
- resolve to `2 adults, 0 children`
- search options

### Grouped option suggestions

- reply groups options by room type name
- each option row includes formatted price
- example:
  - `1. RM 520.00 : Check-in *July 1* - Check-out *July 3*`

### Option selection and confirmation

- `option 2`
- validate against current suggestion set
- save `confirmation_candidate`
- ask for confirmation
- `yes`
- generate real booking link

### Date and room-type disambiguation

- user selects `May 21`
- if several room types share that date, ask for room type
- user replies `ocean villa`
- combine room type + pending date to resolve a unique option
- ask for confirmation

### Partial room-type matching

- accept partial room type names like:
  - `garden prestige`
  - `garden prestige suit`
  - `executive`
- if a room type has exactly one relevant visible option, select it
- if a room type has multiple relevant visible options, re-list only that room type and ask for option number

### Raw option number phrases

- accept selection phrasing like:
  - `i chose option 1`
  - `i choose option 1`
  - `choice 1`
  - `number 1`

### Interruption and resume

- user asks for booking policy mid-booking
- preserve current booking branch
- answer hotel policy question
- user later returns to booking
- resume preserved branch if still valid

### In-flow correction

- user asks for `late july`
- receives options
- later says `late may if possible`
- preserve valid party information
- clear stale options, pending selection, and confirmation state
- rerun booking search for late May

### Another booking branch

- user completes one branch
- later asks for `another booking`
- start a fresh booking branch
- do not reuse prior selected option

## Booking Link Research

The app already has a real quote-link flow that should be reused.

### Existing quote flow

- quote creation happens through `BookingEngine::CreateQuote`
- the API quote controller returns:
  - `booking_url`
  - `total_amount`
  - `currency`
  - `expires_at`

Important: the returned `booking_url` is the public quote/checkout URL, which is the correct concierge CTA after confirmation.

### Inputs needed for real booking-link generation

Minimum:

- `hotel_id`
- `room_type_id`
- `check_in`
- `check_out`

Optional:

- `adults`
- `children`
- `room_count`
- `guest_name`
- `guest_email`
- `guest_phone`

### Consequence for option suggestions

Every suggested option should persist:

- `selection_id`
- `position`
- `room_type_id`
- `room_type_name`
- `check_in`
- `check_out`
- `nights`
- `total_price`
- `currency`

Without `room_type_id`, booking-link generation would need to re-resolve the room later.

## Search Window Support

The interpreter and booking search must understand:

- `early <month>` -> days `1..10`
- `mid <month>` -> days `11..20`
- `late <month>` -> days `21..end_of_month`
- plain month -> full month
- `next month`

This logic should stay deterministic in Ruby, not prompt-only.

## Risk Summary

1. interpreter invents month or date from vague booking interest
2. interpreter invents duration from month-only messages
3. interpreter converts `people` into `adults`
4. stale option sets survive corrections
5. disambiguation loops if pending selection context is not preserved
6. room-type matching is too strict for natural shorthand
7. booking-link generation fails because selected options lack `room_type_id`

## Recommended First Slice

Build first:

1. booking timing
2. duration
3. guest clarification
4. option suggestions with grouped room types and price
5. option selection
6. confirmation
7. booking-link generation

Then expand to:

8. hotel-policy interruption and resume
9. booking context rendering
10. correction handling
11. another-booking branching
