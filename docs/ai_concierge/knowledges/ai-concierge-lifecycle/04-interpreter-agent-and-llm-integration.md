# Interpreter Agent and LLM Integration

## `InterpreterAgent`

- Path: `app/services/ai_concierge/agents/interpreter_agent.rb`
- Input: raw message + compact conversation summary
- Output: structured interpretation only
- No state mutation
- No direct tool execution
- Never trusted for final state changes without Ruby guards
- Classifies internal `message_type` first, then maps to existing `intent` and `topic`

## Interpreter Output Schema

```json
{
  "message_type": "booking_request",
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

`message_type` is internal only. It is not returned in the public API response.

## Supported Message Types

- `booking_request`: guest wants availability, quote, reservation, or booking dates.
- `booking_selection`: guest chooses an option, room, date, or rate plan already shown.
- `booking_confirmation`: guest confirms or rejects a booking candidate when confirmation is pending.
- `hotel_info_question`: hotel services, amenities, transport, parking, breakfast, WiFi, facilities, and similar information.
- `hotel_policy_question`: policies, rules, cancellation, check-in/out, terms, booking requirements, and booking advice.
- `room_info_question`: asks about a room type without trying to book it.
- `existing_booking_question`: asks about an existing booking or reservation context.
- `conversation_control`: reset, cancel attempt, end, resume, or similar conversation controls.
- `greeting_or_unknown`: greeting, unclear message, or unsupported request.

## Required Conversation Signals

- `is_reset`
- `is_resume`
- `is_correction`
- `starts_new_booking_branch`
- `end_conversation`

## Interpreter Rules

- never invent timing from generic booking interest
- never invent duration from month-only messages
- `2 people` means `party_size_total=2`, not `adults=2`
- `yes` is `booking_confirmation` only when the pending question is confirmation-like
- `yes` while asking guest count, duration, adult/children split, or timing must not become booking confirmation
- `option 1` is `booking_selection` only when shown options exist
- `tell me about executive suite` is room information
- `I want executive suite on June 23` is a booking request
- `what should I be aware of during booking in this hotel?` is hotel policy/advice, not booking search
- `this month` without an exact date or `early/mid/late` must not reuse stale timing
- classify user stop phrases such as `stop`, `bye`, and `thanks` as `end_conversation`

## Schema Validation

- Defined in `app/services/ai_concierge/schemas/interpretation_schema.rb`
- Keeps model output shape validated before the rest of the Ruby flow uses it

## `ConversationSummaryBuilder`

- Produces a compact summary of conversation state for the interpreter
- Keeps the model input smaller and focused on relevant context
- Does not include full conversation transcripts by default
- Includes the latest outbound assistant question as `last_assistant_question`
- Includes compact booking option context:
  - `booking_task.shown_options`
  - `booking_task.rate_plan_options`
  - `booking_task.selected_option_summary`

The summary is enough for ambiguous replies such as `yes`, `option 2`, `the cheaper one`, and `what about deluxe?` without paying the cost/noise of full history.
