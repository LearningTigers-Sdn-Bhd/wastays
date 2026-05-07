# AI Concierge V3 Tooling

## Overview

`AiConciergeV3` uses a deterministic tooling pipeline.

- the interpreter classifies `intent`, `topic`, and `slots`
- the transition policy selects the next legal action
- the turn orchestrator delegates to the booking or librarian orchestrator
- the domain orchestrator chooses the registered tool
- the tool returns structured data
- the messenger and message builders render the final guest-facing reply

This means the public tool names in `ToolRegistry` are the runtime contract. The model does not directly execute tools.

## Runtime Flow

1. `InquiryResponder` receives the API request, validates concierge readiness, and requires either `phone` or `prospect_public_id`.
2. `TurnOrchestrator` resolves the hotel-scoped prospect by phone first or by `prospect_public_id` fallback.
3. `TurnOrchestrator` loads persisted conversation state.
4. If the previous conversation was ended, the orchestrator reactivates the same `ProspectConversationState` for the new inbound turn.
5. `TurnOrchestrator` records the inbound message and builds the interpreter summary.
6. Explicit stop/bye/thanks-style messages end the current conversation without running a tool.
7. `InterpreterAgent` returns structured interpretation data.
8. `InformationIntentGuard` corrects unscoped hotel/property amenities and facilities questions to hotel information.
9. `BookingInputNormalizer` strips inferred booking slots that were not explicit in the user message.
10. `TransitionPolicy` converts the interpretation and current state into a high-level deterministic action.
11. `BookingOrchestrator` owns booking sub-steps, booking tools, option selection, confirmation, and URL generation.
12. `LibrarianOrchestrator` owns information tools and information task updates.
13. `ToolRegistry` resolves the tool name to a concrete Ruby class.
14. The selected tool returns structured result data.
15. `MessengerAgent` routes the reply type to a domain message builder.
16. The orchestrator persists state updates and returns the public API payload, including `prospect_public_id` on success.

Booking flows can be interrupted by hotel or room information questions. In those cases `booking_task` is marked `suspended` while `information_task` records the answered knowledge turn. A later option selection or confirmation resumes the suspended booking task before tool execution. General hotel amenities and property facilities questions remain hotel information even after a completed booking.

## Ownership Boundaries

- `TurnOrchestrator`: prospect resolution, state loading, interpreter call, deterministic guard invocation, high-level delegation, persistence, message rendering, and final payload.
- `TransitionPolicy`: high-level action routing only; it does not decide booking sub-steps.
- `BookingOrchestrator`: booking prompts, option search, option selection, confirmation, booking URL generation, booking completion/archive semantics, and safe URL-failure fallback.
- `LibrarianOrchestrator`: hotel policy, general hotel info, FAQ, nearby attractions, room information, `information_task`, and booking suspension on interruptions.
- `ConversationTaskManager`: V2 task-state normalization, legacy read migration, activate/suspend/resume/archive, and avoiding legacy writes.
- `BookingInputNormalizer`: deterministic booking slot guards before merge.
- `InformationIntentGuard`: deterministic hotel/property amenities and facilities correction before routing.

## Tool Registry

Current public tool identifiers:

- `search_booking_options`
- `select_booking_option`
- `generate_booking_url`
- `get_hotel_policy`
- `get_booking_context`
- `get_general_hotel_info`
- `get_hotel_faq`
- `get_nearby_attractions`
- `get_room_type_details`

These names are registered in `app/services/ai_concierge_v3/tools/tool_registry.rb`.

## Tool Groups

### Booking

#### `search_booking_options`

- Path: `app/services/ai_concierge_v3/tools/booking/search_booking_options_tool.rb`
- Purpose: search available booking options for the current branch inputs
- Main inputs: timing, duration, adults, children, room count
- Success output: grouped options with room type identity, dates, prices, positions, and selection IDs
- Example guest questions:
  - `late may`
  - `3 days 2 nights`
  - `2 adults`

#### `select_booking_option`

- Path: `app/services/ai_concierge_v3/tools/booking/select_booking_option_tool.rb`
- Purpose: resolve selection input against the current shown suggestion set
- Main inputs: option number, check-in date, message text, pending selection context
- Success output: selected option payload and suggestion set version
- Failure output:
  - `invalid_selection`
  - `ambiguous_option_selection`
  - `ambiguous_date_selection`
  - `room_type_requires_option_number`
- Example guest questions:
  - `garden prestige suite option 2`
  - `August 3rd`
  - `i chose option 1`

#### `generate_booking_url`

- Path: `app/services/ai_concierge_v3/tools/booking/generate_booking_url_tool.rb`
- Purpose: convert a confirmed option into a booking quote link
- Main inputs: selected option and resolved prospect phone
- Success output: booking URL, total amount, currency, expiry, and quote token
- Lifecycle side effect: successful booking URL generation ends the current conversation with `end_reason: "booking_url_generated"`
- Failure behavior: returns safe fallback and does not archive booking as completed
- Example guest questions:
  - `yes`

### Hotel Information

#### `get_hotel_policy`

- Path: `app/services/ai_concierge_v3/tools/hotel_information/get_hotel_policy_tool.rb`
- Purpose: answer hotel policy questions
- Source order:
  1. `hotel.policy`
  2. fallback to `hotel.property_policy`
- Success output: `policy_text` and/or structured policy fields
- Example guest questions:
  - `what time is check in`
  - `what is your cancellation policy`
  - `what are your hotel rules`

#### `get_booking_context`

- Path: `app/services/ai_concierge_v3/tools/hotel_information/get_booking_context_tool.rb`
- Purpose: answer questions about an existing active booking for the resolved prospect phone number
- Success output: structured booking rows with date range and room type name
- Example guest questions:
  - `what booking do i have`
  - `do i have an active booking`

#### `get_general_hotel_info`

- Path: `app/services/ai_concierge_v3/tools/hotel_information/get_general_hotel_info_tool.rb`
- Purpose: return general hotel details outside policy and booking context
- Main inputs: hotel only
- Success output: name, address, city, country, star rating, mapped hotel amenities, summary text
- Example guest questions:
  - `tell me about the hotel`
  - `where is the hotel located`

#### `get_hotel_faq`

- Path: `app/services/ai_concierge_v3/tools/hotel_information/get_hotel_faq_tool.rb`
- Purpose: return hotel FAQ content
- Main inputs: hotel only
- Success output: `faq_text`
- Example guest questions:
  - `do you have an faq`
  - `what does your faq say`

#### `get_nearby_attractions`

- Path: `app/services/ai_concierge_v3/tools/hotel_information/get_nearby_attractions_tool.rb`
- Purpose: return the full nearby attractions list
- Main inputs: hotel only
- Success output: all nearby attractions with name, description, address, city, and country
- Example guest questions:
  - `what attractions are nearby`
  - `what is around the hotel`
  - `any places to visit nearby`

### Room Information

#### `get_room_type_details`

- Path: `app/services/ai_concierge_v3/tools/room_information/get_room_type_details_tool.rb`
- Purpose: answer room detail questions
- Main inputs: guest message and optional interpreted `room_type_name`
- Success output: matched room type, description, occupancy, and amenity names
- Failure output:
  - `ambiguous_room_type`
  - `room_type_not_found`
- Example guest questions:
  - `tell me about the executive suite`
  - `what amenities does the ocean villa have`

## Intent and Topic Mapping

| Guest question type | Intent | Topic | Action | Tool | Reply type |
| --- | --- | --- | --- | --- | --- |
| booking availability / search | `booking_search` | `booking_search` | booking flow action | booking tools | booking reply types |
| booking option choice | `option_selection` | `booking_search` | high-level `booking`; sub-step option selection | `select_booking_option` | `ask_confirmation` or ambiguity reply |
| booking confirmation | `confirmation` | `booking_search` | high-level `booking`; sub-step confirmation | `generate_booking_url` on yes | `booking_link_ready` or decline reply |
| active booking lookup | `booking_context` | `booking_context` | `booking_context` | `get_booking_context` | `booking_context` |
| check-in / check-out / cancellation | `hotel_policy` | `hotel_policy` | `hotel_policy` | `get_hotel_policy` | `hotel_policy` |
| general hotel facts | `hotel_information` | `general_hotel_info` | `hotel_information` | `get_general_hotel_info` | `general_hotel_info` |
| hotel FAQ | `hotel_information` | `hotel_faq` | `hotel_information` | `get_hotel_faq` | `hotel_faq` |
| nearby places / attractions | `nearby_attractions` | `nearby_attractions` | `nearby_attractions` | `get_nearby_attractions` | `nearby_attractions` |
| room details / amenities / occupancy | `room_information` | `room_information` | `room_information` | `get_room_type_details` | `room_type_details` |
| end current conversation | any low-confidence or conversational intent with `end_conversation` signal | any | `end_conversation` | none | terminal conversation reply |

## Identity and Continuation

- API clients should store `prospect_public_id` from successful responses.
- A later request can continue the same prospect conversation with `prospect_public_id` when `phone` is unavailable.
- If both `phone` and `prospect_public_id` are provided, `phone` takes precedence.
- `prospect_public_id` lookup is scoped to the current hotel.
- Invalid public IDs return `404`; missing identity returns `422`.
- Booking-context lookup and booking URL generation use the resolved prospect phone, so public-ID continuation still has access to the original phone-backed booking context.

## Conversation Lifecycle

- `ProspectConversationState` is the durable state container for V3.
- Anonymous/incognito state is not part of the runtime contract.
- Lifecycle metadata is persisted under `slots_payload["conversation"]`.
- Stop phrases such as `stop`, `bye`, and `thanks` end the current conversation only; they do not unsubscribe the guest.
- A new valid inbound message after an ended conversation reactivates the same conversation state.

## Operator Examples

### Booking Examples

- `late may`
- `4 days 3 nights`
- `2 adults`
- `garden prestige suite option 2`
- `yes`

### Hotel Information Examples

- `what time is check in`
- `tell me about the hotel`
- `do you have an faq`
- `what attractions are nearby`

### Room Information Examples

- `tell me about the executive suite`
- `what amenities does the executive suite have`

### Contrast Examples

- `tell me about executive suite` -> room information
- `i want executive suite on may 22` -> booking flow, not room information
- `may i know hotel amenities` -> hotel information, not room information
- `available facilities?` -> hotel information, not room information
- `what attractions are nearby` -> nearby attractions, not general hotel info
- `what time is check in` -> hotel policy, not general hotel info

## Pause and Resume Behavior

- hotel and room information questions can interrupt an active booking flow
- the active booking task is suspended, not discarded
- after the information reply, selection-like booking follow-ups resume the suspended booking task
- informational intents should be preserved as informational requests rather than being forced through option selection
- expired suspended booking tasks do not resume

Examples:

- booking flow -> `any hotel policies?` -> policy reply -> `ok i want executive on may 22` resumes booking selection
- booking flow -> `tell me about the executive suite` -> room details reply -> `option 2 please` resumes booking selection

## Room Matching

Room information tools share `app/services/ai_concierge_v3/matching/room_type_matcher.rb`.

Matching behavior:

1. exact normalized room-name match
2. fuzzy token and prefix matching against the guest message
3. ambiguous match result when multiple room types fit
4. not-found result when no room type matches

Examples:

- `exec suite` -> `Executive Suite`
- `ocean villa` -> ambiguous if both `Ocean Villa King` and `Ocean Villa Twin` exist

## Reply Rendering

Reply types are rendered by domain builders.

- `BookingActionsBuilder`
  - booking prompts and specific timing clarification (`early/mid/late`)
  - option rendering with bolded prices/room types and public hotel search link
  - structured multiline confirmation prompts enriched with DB amenities
  - booking-link replies with bolded total and expiry
- `HotelInfoBuilder`
  - hotel policy
  - booking context
  - general hotel info
  - hotel FAQ
  - nearby attractions
- `RoomInfoBuilder`
  - room details
  - ambiguous room match
  - room not found
- `FallbackBuilder`
  - safe fallback payloads when the normal flow cannot complete

## Testing Map

Primary request coverage:

- `spec/requests/api/v1/ai_concierge/inquiries_spec.rb`

Tool specs:

- booking tools under `spec/services/ai_concierge_v3/tools/`
- hotel information tools under `spec/services/ai_concierge_v3/tools/`
- room information tools under `spec/services/ai_concierge_v3/tools/`

Shared utility coverage:

- `spec/services/ai_concierge_v3/matching/room_type_matcher_spec.rb`
- `spec/services/ai_concierge_v3/orchestration/booking_input_normalizer_spec.rb`
- `spec/services/ai_concierge_v3/orchestration/information_intent_guard_spec.rb`

Domain orchestrator coverage:

- `spec/services/ai_concierge_v3/orchestration/booking_orchestrator_spec.rb`
- `spec/services/ai_concierge_v3/orchestration/librarian_orchestrator_spec.rb`

Reply-format coverage:

- `spec/services/ai_concierge_v3/agents/messenger_agent_spec.rb`

This test surface covers booking search, selection, confirmation, hotel information, room information, ambiguity handling, public-ID continuation, lifecycle end/reactivation, and interruption/resume behavior.
