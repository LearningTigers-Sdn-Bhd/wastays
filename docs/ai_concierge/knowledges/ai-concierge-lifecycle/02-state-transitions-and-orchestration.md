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

Thin coordinator for a single concierge turn:

1. ask `Conversation::SessionLoader` to resolve/create the prospect, lock the turn, load/reactivate state, and record inbound message
2. return `Conversation::ControlHandler` max-turn response when the conversation exceeds the turn limit
3. ask `Conversation::InterpretationPipeline` to call the interpreter and validate the structured result
4. return `Conversation::ControlHandler` result when cancellation/end controls apply
5. ask `Conversation::InterpretationPipeline` to guard, merge, and decide the legal route
6. delegate booking actions to `Booking::Orchestrator`
7. delegate information actions to `HotelKnowledge::Orchestrator`
8. delegate existing-booking context to `Conversation::BookingContextHandler`
9. ask `Conversation::ResponsePersister` to render, persist, record outbound, and return the public payload

## `Booking::Orchestrator`

Coordinates booking sub-step execution after high-level transition is `:booking` or `:resume`:
- timing, duration, guest count follow-ups
- search booking options
- resolve option selections
- ask rate plan when an option has multiple rate plans
- delegate next-step resolution to `Booking::ActionResolver`
- delegate option ambiguity to `Booking::SelectionHandler`
- delegate rate plan selections through `Booking::RatePlanSelectionHandler` and `RatePlanMatcher`
- delegate booking URL generation and archive behavior to `Booking::CompletionHandler`
- delegate suspended booking resume to `Booking::ResumeHandler`
- apply booking-ready rate/room revision decisions from `Booking::RevisionPolicy`
- preserve `pending_selection` for ambiguous follow-ups
- generate booking URLs with selected rate plan pricing
- archive completed booking tasks only after successful URL generation
- safe fallback on URL generation failure

## Policy and Matcher Objects

`Core::ConversationControlPolicy` owns deterministic conversation-control checks:
- explicit booking-attempt cancellation
- explicit end requests
- end-confirmation yes/no interpretation
- end-confirmation mode (`generic`, `continue_booking`, or `cancel_booking_attempt`)

`Booking::RevisionPolicy` owns booking-ready revision detection:
- `change rate` / `show rates again` -> `:change_rate`
- `change room` / `different option` -> `:change_option`
- blocks revision when the message is informational, confirmation, ending the conversation, changing timing/party slots, or already answering rate-plan selection

`RatePlanMatcher` owns deterministic rate-plan matching:
- exact or unique partial names
- ordinal replies
- price intent
- unique `standard`
- refundable/non-refundable distinction

## `HotelKnowledge::Orchestrator`

Coordinates information tool execution after high-level transition is `:librarian`:
- hotel policy, general hotel info, FAQ, nearby attractions, room information
- delegate intent/topic tool routing to `HotelKnowledge::ToolRouter`
- delegate room result mapping to `HotelKnowledge::RoomReplyResolver`
- delegate `information_task` and booking suspension payload updates to `HotelKnowledge::StateHandler`
- delegate diagnostic creation context to `HotelKnowledge::DiagnosticRecorder`
- passes the raw guest message as `query` to hybrid hotel knowledge tools
- hotel knowledge categories are treated as storage categories; answer retrieval may retry across `general_info`, `faq`, and `policy` when the routed category has no useful match
- update `information_task` for each answered knowledge turn
- suspend active booking tasks only when `pause: true`
- leave active booking unsuspended when `pause: false`

## `MessengerAgent`

- accept structured reply context
- produce deterministic `reply_message`
- format grouped room options with bolded prices/room types
- format multiline confirmation and quote replies
- not allowed to set: `action_name`, `needs_human_support`, state patches

## `Core::TransitionPolicy`

Enforces high-level legal routing:
- `:end_conversation`, `:reset`, `:resume`, `:librarian`, `:booking_context`, `:booking`, `:greeting`, or `:fallback`
- resume non-expired suspended bookings before general routing when inbound is selection/confirmation follow-up
- route information intents during active booking to librarian with `pause: true`
- route information intents outside active booking to librarian with `pause: false`
- policy phrasing corrected by `Core::InformationIntentGuard` before routing, including "booking policy", policies/rules/house rules, cancellation, check-in, and check-out questions
- hotel service questions corrected by `Core::InformationIntentGuard` before routing, including parking, transportation, shuttle/airport transfer, WiFi, breakfast, restaurant, spa, pool, amenities, and facilities
- hotel booking-advice questions corrected by `Core::InformationIntentGuard` before routing, including "what should I be aware of during booking"
- clear booking requests still remain booking flow, including book/reserve/quote, room availability, and date/month booking phrasing
- suspended booking resumes only for selection/confirmation/booking follow-ups, not hotel information or policy interruptions

## `ConversationTaskManager`

- normalize legacy `active` and `paused_flows` state into V2 task state on read
- write new state using `state_version: 2`
- activate, suspend, resume, expire, and archive booking tasks
- reset the active booking task when the guest cancels the booking attempt
- update `information_task`
- avoid writing legacy `active` and `paused_flows` keys

## Booking Attempt Cancellation

Cancel-attempt phrases such as `cancel attempt`, `cancel booking attempt`, and `cancel my attempt for booking` do not continue a stale booking branch.

These checks are owned by `Core::ConversationControlPolicy` and run before end-confirmation and generic explicit-end handling.

They:

1. reset `booking_task` to `idle`
2. clear `active_flow`, `active_topic`, and `pending_question`
3. keep the conversation active
4. ask whether the guest wants to start a new booking, ask hotel policies/information, or end the conversation

A follow-up generic booking request such as `I want to make booking` starts fresh and asks for dates or month.
