# Interpreter Agent and LLM Integration

## `InterpreterAgent`

- Path: `app/services/ai_concierge_v3/agents/interpreter_agent.rb`
- Input: raw message + compact conversation summary
- Output: structured interpretation only
- No state mutation
- No direct tool execution
- Never trusted for final state changes without Ruby guards

## Interpreter Output Schema

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
- classify user stop phrases such as `stop`, `bye`, and `thanks` as `end_conversation`

## Schema Validation

- Defined in `app/services/ai_concierge_v3/schemas/interpretation_schema.rb`
- Keeps model output shape validated before the rest of the Ruby flow uses it

## `ConversationSummaryBuilder`

- Produces a compact summary of conversation state for the interpreter
- Keeps the model input smaller and focused on relevant context
