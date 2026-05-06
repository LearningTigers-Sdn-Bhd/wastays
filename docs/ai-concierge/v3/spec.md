# AI Concierge V3 Specification

## Objective

Implement `AiConciergeV3` as a stateful concierge workflow with:

- structured LLM interpretation
- deterministic Ruby orchestration
- typed tools
- deterministic guest-facing reply rendering

## Public API Contract

V3 runs behind the existing endpoint and response shape.

### Request

- `message`
- optional `phone`
- optional `prospect_public_id`

Identity requirements:

- requests must include either `phone` or `prospect_public_id`
- when `phone` is present, the concierge resolves or creates the prospect from the hotel-scoped phone number
- when `phone` is absent and `prospect_public_id` is present, the concierge resumes the hotel-scoped prospect by public ID
- requests with neither identity return `422`
- requests with an unknown `prospect_public_id` return `404`

### Response

- `reply_message`
- `needs_human_support`
- `action_name`
- `prospect_public_id`

## Module Layout

Current implementation under `app/services/ai_concierge_v3/`:

- `orchestration/inquiry_responder.rb`
- `orchestration/turn_orchestrator.rb`
- `orchestration/result.rb`
- `orchestration/response_payload_builder.rb`
- `orchestration/transition_policy.rb`
- `agents/interpreter_agent.rb`
- `agents/messenger_agent.rb`
- `state/branch_manager.rb`
- `state/slot_merger.rb`
- `state/state_patch_builder.rb`
- `fallback_builder.rb`
- `conversation_summary_builder.rb`
- `tools/tool_registry.rb`

Current tool implementation under `app/services/ai_concierge_v3/tools/`:

- `booking/search_booking_options_tool.rb`
- `booking/select_booking_option_tool.rb`
- `booking/generate_booking_url_tool.rb`
- `hotel_information/get_hotel_policy_tool.rb`
- `hotel_information/get_booking_context_tool.rb`
- `hotel_information/get_general_hotel_info_tool.rb`
- `hotel_information/get_hotel_faq_tool.rb`
- `hotel_information/get_nearby_attractions_tool.rb`
- `room_information/get_room_type_details_tool.rb`

Current schema implementation under `app/services/ai_concierge_v3/schemas/`:

- `interpretation_schema.rb`

## Responsibilities

### `InquiryResponder`

- validate hotel AI readiness
- normalize incoming message, phone, and prospect public ID
- reject requests without a usable prospect identity
- call orchestrator
- return fallback on unexpected exceptions

### `InterpreterAgent`

- input: raw message + compact conversation summary
- output: structured interpretation only
- no state mutation
- no direct tool execution
- never trusted for final state changes without Ruby guards

### `TurnOrchestrator`

- resolve or create prospect
- load persisted conversation state
- reactivate an ended conversation state when a new inbound turn arrives
- record inbound message
- call interpreter
- apply deterministic timing, duration, and guest-count guards (stripping hallucinated `check_in` and `month_segment`)
- merge incoming slots into active branch, supporting pure digit extraction for guest counts
- decide next legal action
- call deterministic tools
- build state patch
- call messenger
- record inbound and outbound prospect messages
- explicitly archive active branches on conversation end to prevent state leakage
- return final payload

### `MessengerAgent`

- accept structured reply context
- produce deterministic user-facing `reply_message`
- format grouped room options with bolded prices/room types and public hotel search links
- enrichment from `RoomType` descriptions and `Hotel::ROOM_AMENITIES`
- format structured multiline confirmation and quote replies
- not allowed to set:
  - `action_name`
  - `needs_human_support`
  - state patches

### `StatePatchBuilder`

- centralize conversation-state persistence metadata
- persist active flow, pending question, and slots payload
- update lifecycle metadata under `slots_payload["conversation"]`

### `TransitionPolicy`

- enforce legal next actions from current state
- current order:
  1. explicit end conversation -> end current conversation
  2. missing timing -> ask booking timing
  3. timing exists but duration missing -> ask duration
  4. children-only guest input -> ask adult count
  5. guest count missing -> ask guest count
  6. `party_size_total` without adult/child split -> ask clarification
  7. resolved booking inputs -> search or continue selection/confirmation flow

### `SlotMerger`

- merge new slots into active branch
- preserve valid upstream slots across corrections
- normalize `days`, `nights`, and derived `check_out`
- clear stale downstream state when timing or party composition changes

### `BranchManager`

- start fresh booking branches
- store short-lived completed branches
- pause and resume active booking branches

## Interpreter Contract

The interpreter must return a strict structure.

```json
{
  "intent": "booking_search",
  "topic": "booking_search",
  "confidence": 0.94,
  "slots": {
    "target_month": 7,
    "target_year": 2026,
    "month_segment": "late",
    "party_size_total": 2
  },
  "tool_hints": ["search_booking_options"],
  "conversation_signals": {
    "is_reset": false,
    "is_resume": false,
    "is_correction": false,
    "starts_new_booking_branch": false,
    "end_conversation": false
  }
}
```

Required conversation signals:

- `is_reset`
- `is_resume`
- `is_correction`
- `starts_new_booking_branch`
- `end_conversation`

Interpreter rules:

- never invent timing from generic booking interest
- never invent duration from month-only messages
- `2 people` means `party_size_total=2`, not `adults=2`
- classify user stop phrases such as `stop`, `bye`, and `thanks` as `end_conversation`

## Messenger Contract

Messenger input is structured and business-safe.

### Suggestion Reply Example

```json
{
  "reply_type": "suggest_options",
  "month_label": "early July 2026",
  "guest_label": "2 adults",
  "options": [
    {
      "room_type_id": 123,
      "room_type_name": "Ocean Villa King",
      "options": [
        {
          "selection_id": "room_type_123_option_1",
          "position": 1,
          "check_in": "2026-07-01",
          "check_out": "2026-07-03",
          "nights": 2,
          "total_price": 520.0,
          "currency": "MYR"
        }
      ]
    }
  ]
}
```

### Booking Link Reply Example

```json
{
  "reply_type": "booking_link_ready",
  "result": {
    "booking_url": "https://...",
    "total_amount": 520.0,
    "currency": "MYR",
    "expires_at": "2026-05-04T15:15:00Z",
    "selected_option": {
      "room_type_name": "Ocean Villa King",
      "check_in": "2026-07-25",
      "check_out": "2026-07-27"
    }
  }
}
```

Messenger output:

```json
{
  "reply_message": "..."
}
```

## Conversation State Contract

Use `ProspectConversationState` as the durable state container. Anonymous or incognito conversation state is not supported in V3.

### Prospect Identity

- `Prospect#public_id` is the public continuation token returned to API clients as `prospect_public_id`.
- `phone` takes precedence over `prospect_public_id` when both are present.
- `prospect_public_id` lookup is scoped to the current hotel.
- Phone-less new prospect creation is not supported; a phone-less request can only continue an existing prospect by `prospect_public_id`.
- `ProspectProfileFact` is not part of the current state model; profile and conversation memory live in `ProspectConversationState` for this V3 pass.

### `slots_payload["conversation"]`

```json
{
  "status": "active",
  "started_at": "2026-05-06T09:00:00Z",
  "last_user_message_at": "2026-05-06T09:02:00Z",
  "ended_at": null,
  "end_reason": null,
  "turn_count": 2
}
```

Lifecycle rules:

- `started_at` is set when lifecycle metadata is first created.
- `last_user_message_at` updates on every persisted inbound turn.
- `turn_count` increments on every persisted state patch.
- explicit user stop phrases end only the current conversation and set `end_reason` to `user_ended`.
- successful booking URL generation ends the current conversation and sets `end_reason` to `booking_url_generated`.
- a later valid inbound message reactivates the same `ProspectConversationState` rather than creating anonymous state.

Use the following booking-state `slots_payload` conventions.

### `slots_payload["active"]`

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

### `pending_selection`

```json
{
  "check_in": "2026-05-21",
  "room_type_name": "Ocean Villa King",
  "candidate_room_type_names": ["Ocean Villa King", "Executive Penthouse"]
}
```

### `slots_payload["paused_flows"]`

```json
[
  {
    "topic": "booking_search",
    "flow": "booking_search",
    "pending_question": "select_option",
    "slots": {},
    "updated_at": "...",
    "expires_at": "..."
  }
]
```

### `slots_payload["completed_booking_branches"]`

```json
[
  {
    "branch_id": "uuid",
    "selected_option": {},
    "completed_at": "..."
  }
]
```

## Search Window Rules

- `early august` -> days `1..10`
- `mid august` -> days `11..20`
- `late august` -> days `21..end_of_month`
- `august` -> whole month
- `next month` -> next calendar month

## Tool Specifications

### `SearchBookingOptionsTool`

Inputs:

- `hotel`
- `target_month`
- `target_year`
- `month_segment`
- optional `check_in`
- optional `check_out`
- `adults`
- `children`
- `room_count`
- `nights`

Output:

```json
[
  {
    "room_type_id": 123,
    "room_type_name": "Ocean Villa King",
    "options": [
      {
        "selection_id": "room_type_123_option_1",
        "position": 1,
        "check_in": "2026-07-01",
        "check_out": "2026-07-03",
        "nights": 2,
        "total_price": 520.0,
        "currency": "MYR",
        "adults": 2,
        "children": 0,
        "room_count": 1
      }
    ]
  }
]
```

### `SelectBookingOptionTool`

Inputs:

- optional `option_number`
- `suggested_options`
- `suggestion_set_version`
- optional `selection_id`
- optional `check_in`
- raw `message`
- optional `pending_selection`

Outputs:

- selected option on success
- recoverable invalid-selection result on failure
- ambiguity results:
  - `ambiguous_option_selection`
  - `ambiguous_date_selection`
  - `room_type_requires_option_number`

Supported selection styles:

- `Ocean Villa King option 1`
- `Executive Penthouse on May 21`
- `option 1` when only one room-type group is relevant
- `i chose option 1`
- partial room type matches like `garden prestige` and `executive`

### `GenerateBookingUrlTool`

Inputs:

- `hotel_id`
- `room_type_id`
- `check_in`
- `check_out`
- `adults`
- `children`
- `room_count`
- optional guest details

Outputs:

- `booking_url`
- `total_amount`
- `currency`
- `expires_at`
- `quote_token`

### `GetHotelPolicyTool`

Inputs:

- `hotel`
- policy topic

Outputs:

- structured hotel policy facts

### `GetBookingContextTool`

Inputs:

- `hotel`
- `phone`

Outputs:

```json
{
  "bookings": [
    {
      "date_range": "May 21 - May 23",
      "room_type_name": "Executive Penthouse"
    }
  ]
}
```

## Transition Rules

1. explicit stop/bye/thanks/nevermind message -> end the current conversation (highest precedence)
2. no date window or concrete dates -> ask for booking timing
3. vague month without specific date or segment -> ask for specific timing (early/mid/late)
4. booking timing exists but duration missing -> ask duration
5. children exist without adults -> ask adult count
6. guest count missing -> ask guest count
7. `party_size_total` exists but adult/children split missing -> ask clarification (smart split with remainder suggestion)
8. valid option selection -> set `confirmation_candidate` and ask for confirmation
9. confirmation `yes` -> generate booking link and end the current conversation
10. confirmation `no` -> clear candidate and return to option selection
11. hotel-policy question during booking -> pause booking branch and answer policy
12. return with option selection -> resume paused branch if still valid
13. `another booking` -> archive completed branch and start fresh branch
14. change of month/window or party composition -> clear stale suggestions, pending selection, and confirmation state, then rerun search

## Required State Invalidation

When booking timing changes, clear:

- `suggested_options`
- `pending_selection`
- `confirmation_candidate`
- `selected_option`

When party composition changes, clear:

- `suggested_options`
- `pending_selection`
- `confirmation_candidate`
- `selected_option`

## Final Booking Reply Requirement

After explicit confirmation, the concierge must return a reply that includes:

- booking URL
- total amount
- expiry time

Example structure:

> Your booking link is ready for July 25 to July 27.  
> Total: RM 520.00  
> This link expires at 3:15 PM.  
> Quotation link: `https://...`

## Test Coverage Requirements

### Service specs

- `inquiry_responder_spec.rb`
- `turn_orchestrator_spec.rb`
- `slot_merger_spec.rb`
- `transition_policy_spec.rb`
- `branch_manager_spec.rb`
- `state_patch_builder_spec.rb`
- `interpreter_agent_spec.rb`
- `messenger_agent_spec.rb`
- `tools/search_booking_options_tool_spec.rb`
- `tools/select_booking_option_tool_spec.rb`
- `tools/generate_booking_url_tool_spec.rb`
- `tools/get_hotel_policy_tool_spec.rb`
- `tools/get_booking_context_tool_spec.rb`

### Request scenarios

1. vague booking + guest count only -> ask booking timing
2. month window -> ask duration
3. `2 people` stays unresolved until adult/children split is given
4. grouped room-type options are rendered with price
5. unique date reply selects the shown option
6. ambiguous date reply lists matching room type names
7. room type reply after ambiguous date does not loop
8. `i chose option 1` works when option number is unambiguous
9. room-type shorthand like `executive one` asks for option number under that room type
10. confirmed option returns booking URL with total and expiry
11. booking question -> hotel policy -> preserved options -> selection
12. booking context returns a structured booking list
13. `late july` -> `late may` correction invalidates old options
14. completed booking -> `another booking`
15. missing phone and missing `prospect_public_id` returns `422`
16. valid `prospect_public_id` continues the existing prospect conversation
17. invalid `prospect_public_id` returns `404`
18. explicit end message ends the current conversation
19. new inbound message reactivates an ended conversation state
20. booking URL generation marks the current conversation ended
