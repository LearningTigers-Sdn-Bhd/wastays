# Conversation State Management

## Data Models

- `Prospect`: Guest identified by `phone_number` scoped to hotel; has `public_id` for session continuation
- `ProspectConversationState`: Durable JSON state container (`slots_payload`) for V3 conversations
- `ProspectMessage`: Inbound/outbound/system message log

## Prospect Identity

- `Prospect#public_id` is the public continuation token returned as `prospect_public_id`
- `phone` takes precedence over `prospect_public_id` when both are present
- `prospect_public_id` lookup is scoped to the current hotel
- Phone-less new prospect creation is not supported

## `slots_payload["conversation"]`

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

## Lifecycle Rules

- `started_at` is set when lifecycle metadata is first created
- `last_user_message_at` updates on every persisted inbound turn
- `turn_count` increments on every persisted state patch
- explicit user stop phrases end only the current conversation (`end_reason: "user_ended"`)
- successful booking URL generation ends the current conversation (`end_reason: "booking_url_generated"`)
- a later valid inbound message reactivates the same `ProspectConversationState`
- booking attempt cancellation resets `booking_task` but keeps the conversation active so the guest can choose the next step

## `slots_payload["booking_task"]`

```json
{
  "status": "waiting_for_option_selection",
  "pending_question": "select_option",
  "branch": {
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
    "selected_option": null,
    "selected_rate_plan_id": null,
    "selected_rate_plan_name": null
  },
  "suspended": false,
  "suspended_at": null,
  "expires_at": null,
  "interruption_count": 0,
  "last_interruption_intent": null,
  "last_interruption_topic": null
}
```

## `slots_payload["information_task"]`

```json
{
  "status": "completed",
  "intent": "hotel_policy",
  "topic": "hotel_policy",
  "last_question": "what time is check in?",
  "answered_at": "..."
}
```

- Information turns update `information_task` and may suspend `booking_task`
- They do not erase booking options or confirmation candidates

## Compact Interpreter Summary

The interpreter does not receive full conversation history by default. `ConversationSummaryBuilder` sends compact state instead:

```json
{
  "last_assistant_question": "For 5 people, how many are adults and how many are children?",
  "booking_task": {
    "status": "waiting_for_option_selection",
    "pending_question": "select_option",
    "shown_options": [
      {
        "position": 1,
        "selection_id": "option-uuid",
        "room_type_name": "Deluxe Room",
        "check_in": "2026-06-23",
        "check_out": "2026-06-26"
      }
    ],
    "rate_plan_options": [
      { "position": 1, "name": "Standard Rate" },
      { "position": 2, "name": "Non-Refundable" }
    ],
    "selected_option_summary": {
      "room_type_name": "Deluxe Room",
      "check_in": "2026-06-23",
      "check_out": "2026-06-26",
      "rate_plan_name": "Standard Rate"
    }
  }
}
```

This lets the interpreter understand compact follow-ups without loading noisy transcripts.

## `slots_payload["completed_booking_branches"]`

```json
[
  {
    "branch_id": "uuid",
    "selected_option": {},
    "completed_at": "..."
  }
]
```

## `StatePatchBuilder`

- centralize conversation-state persistence metadata
- persist active flow, pending question, and V2 task-state slots payload
- update lifecycle metadata under `slots_payload["conversation"]`
