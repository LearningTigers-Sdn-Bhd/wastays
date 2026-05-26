# State Transitions and Orchestration

## Public API Contract

### Request
- `message`
- optional `phone`
- optional `prospect_public_id`

Identity rules:
- must include either `phone` or `prospect_public_id`
- `phone` resolves or creates the prospect from the hotel-scoped phone number
- `prospect_public_id` resumes the hotel-scoped prospect by public ID
- neither -> `422`
- unknown `prospect_public_id` -> `404`

### Response
- `reply_message`
- `needs_human_support`
- `action_name`
- `prospect_public_id`

## `TurnOrchestrator`

Central coordinator for a single concierge turn:

1. resolve or create prospect
2. load persisted conversation state
3. reactivate an ended conversation state when a new inbound turn arrives
4. record inbound message
5. call interpreter
6. apply `InformationIntentGuard` and `BookingInputNormalizer`
7. merge incoming slots into active branch
8. decide next legal action via `TransitionPolicy`
9. delegate booking actions to `BookingOrchestrator`
10. delegate information actions to `LibrarianOrchestrator`
11. build state patch
12. call messenger
13. record inbound and outbound prospect messages
14. explicitly archive active branches on conversation end
15. return final payload

## `BookingOrchestrator`

Owns booking sub-step decisions after high-level transition is `:booking` or `:resume`:
- timing, duration, guest count follow-ups
- search booking options
- resolve option selections
- ask rate plan when an option has multiple rate plans
- resolve rate plan selections with fuzzy name matching
- preserve `pending_selection` for ambiguous follow-ups
- generate booking URLs with selected rate plan pricing
- archive completed booking tasks only after successful URL generation
- safe fallback on URL generation failure

## `LibrarianOrchestrator`

Owns information tool routing:
- hotel policy, general hotel info, FAQ, nearby attractions, room information
- update `information_task` for each answered knowledge turn
- suspend active booking tasks only when `pause: true`
- leave active booking unsuspended when `pause: false`

## `MessengerAgent`

- accept structured reply context
- produce deterministic `reply_message`
- format grouped room options with bolded prices/room types
- format multiline confirmation and quote replies
- not allowed to set: `action_name`, `needs_human_support`, state patches

## `TransitionPolicy`

Enforces high-level legal routing:
- `:end_conversation`, `:reset`, `:resume`, `:librarian`, `:booking_context`, `:booking`, `:greeting`, or `:fallback`
- resume non-expired suspended bookings before general routing when inbound is selection/confirmation follow-up
- route information intents during active booking to librarian with `pause: true`
- route information intents outside active booking to librarian with `pause: false`

## `ConversationTaskManager`

- normalize legacy `active` and `paused_flows` state into V2 task state on read
- write new state using `state_version: 2`
- activate, suspend, resume, expire, and archive booking tasks
- update `information_task`
- avoid writing legacy `active` and `paused_flows` keys
