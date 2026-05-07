# AI Concierge V3 Tests

## Overview

This document maps the current test surface for `AiConciergeV3`.

- `spec.md` defines behavior and state contracts
- `tooling.md` maps intents, topics, tools, and runtime reply types
- this file explains which specs cover those behaviors

## How To Read The Suite

1. Start with `spec/requests/api/v1/ai_concierge/inquiries_spec.rb` for end-to-end concierge behavior.
2. Read `turn_orchestrator_spec.rb`, `transition_policy_spec.rb`, `booking_orchestrator_spec.rb`, `librarian_orchestrator_spec.rb`, and `slot_merger_spec.rb` for core flow control.
3. Read the tool specs under `spec/services/ai_concierge_v3/tools/` for isolated booking, hotel-information, and room-information logic.
4. Read `matching/room_type_matcher_spec.rb` for fuzzy room resolution behavior.
5. Read `messenger_agent_spec.rb` for deterministic guest-facing reply formatting.

## Service Specs

### `spec/services/ai_concierge_v3/orchestration/inquiry_responder_spec.rb`

- verifies disabled-concierge failure behavior
- verifies successful delegation for hotels with concierge enabled
- verifies missing identity is rejected with `422`

### `spec/services/ai_concierge_v3/orchestration/turn_orchestrator_spec.rb`

- verifies the top-level deterministic guard flow (stripping hallucinated `check_in` and `month_segment`)
- covers duration-first handling for month-window requests
- covers rejecting invented timing for vague booking messages
- covers specific timing clarification flow (`early/mid/late`)
- covers preserving `2 people` as unresolved until adult and child split is clarified
- covers pure digit extraction for guest counts
- covers prospect continuation by `prospect_public_id`
- covers invalid public ID returning a not-found result
- covers explicit end-conversation handling and reactivation of ended state
- covers explicit abandonment precedence (fixing the selection loop bug)
- covers booking URL generation ending the current conversation
- covers suspended booking confirmation resuming after an information turn
- verifies `TurnOrchestrator` coordinates rather than owning booking or librarian domain logic directly

### `spec/services/ai_concierge_v3/orchestration/booking_orchestrator_spec.rb`

- verifies room-type-only selection when exactly one visible option exists
- verifies named room types with multiple visible options ask for option number
- verifies ambiguous option-number selections ask for room type clarification
- verifies ambiguous date selections ask for room type clarification
- verifies pending date context resolves room-type follow-ups without looping
- verifies booking URL generation failure returns a safe fallback
- verifies booking URL generation failure does not archive the booking as completed

### `spec/services/ai_concierge_v3/orchestration/librarian_orchestrator_spec.rb`

- verifies hotel policy interruptions return the shared domain result contract and suspend active booking
- verifies general hotel information, hotel FAQ, nearby attractions, and room information success contracts
- verifies ambiguous room information and unknown room-type contracts
- verifies `pause: false` updates information state without suspending active booking
- verifies `pause: true` suspends active booking with preserved branch metadata

### `spec/services/ai_concierge_v3/state/slot_merger_spec.rb`

- verifies follow-up resolution from `2 people` to `adults`
- verifies smart party split suggestions and confirmation
- verifies stale downstream state is cleared when timing changes
- verifies derived `nights` and `check_out` from `days` and `check_in`

### `spec/services/ai_concierge_v3/orchestration/transition_policy_spec.rb`

- verifies high-level routing to booking while booking sub-steps remain in `BookingOrchestrator`
- verifies end-conversation has highest precedence
- verifies suspended or paused booking flows resume before validating selection-like follow-ups
- verifies deterministic action routing for hotel-policy, hotel-information, nearby-attractions, and room-information intents
- verifies pending booking follow-ups beat greeting routing
- verifies information intents during option selection route to librarian instead of booking selection
- verifies completed booking state does not block later hotel amenities routing

### `spec/services/ai_concierge_v3/state/conversation_task_manager_spec.rb`

- verifies legacy `active` state normalizes into V2 `booking_task`
- verifies suspended booking state resumes without losing confirmation candidates
- verifies expired suspended booking state does not resume

### `spec/services/ai_concierge_v3/state/branch_manager_spec.rb`

- verifies legacy branch pause/resume behavior kept for compatibility coverage

### `spec/services/ai_concierge_v3/state/conversation_summary_builder_spec.rb`

- verifies compact V2 task context is exposed to the interpreter
- verifies legacy state summaries normalize into task-shaped context

### `spec/services/ai_concierge_v3/state/state_patch_builder_spec.rb`

- verifies persisted slots payload is normalized into V2 task state without legacy `active` or `paused_flows`
- verifies lifecycle metadata under `slots_payload["conversation"]`
- verifies `last_user_message_at` updates each persisted turn
- verifies end reasons are persisted

### `spec/services/ai_concierge_v3/agents/interpreter_agent_spec.rb`

- verifies schema-shaped interpretation output for booking timing and total guest count extraction
- covers the structured interpreter contract used by booking, hotel information, and room information flows
- verifies the required `end_conversation` signal shape

### `spec/services/ai_concierge_v3/agents/messenger_agent_spec.rb`

- verifies deterministic greeting formatting
- verifies grouped room-type option rendering with bolded price formatting and public hotel search link
- verifies narrowed room-type option prompts
- verifies multiline confirmation formatting with DB-sourced descriptions and amenities
- verifies hotel policy block formatting
- verifies structured booking-context rendering for present and empty states
- verifies specific timing clarification prompt rendering

### `spec/services/ai_concierge_v3/orchestration/booking_input_normalizer_spec.rb`

- verifies hallucinated timing is stripped from vague booking messages
- verifies specific timing answers are preserved for specific timing clarifications
- verifies duration slots are kept only when explicit
- verifies pure numeric guest-count answers are extracted for guest-count prompts
- verifies correction turns bypass filtering

### `spec/services/ai_concierge_v3/orchestration/information_intent_guard_spec.rb`

- verifies unscoped facilities questions route to hotel information
- verifies hotel amenities questions route to hotel information
- verifies named room amenities questions stay on room information

### `spec/services/ai_concierge_v3/matching/room_type_matcher_spec.rb`

- verifies exact room-name matching
- verifies fuzzy room-name matching
- verifies ambiguous room-type results
- verifies room-not-found results

## Tool Specs

### Booking Tools

#### `spec/services/ai_concierge_v3/tools/search_booking_options_tool_spec.rb`

- verifies grouped booking options include room type identity, positions, and selection IDs
- verifies the date alignment algorithm scoring and synchronization

#### `spec/services/ai_concierge_v3/tools/select_booking_option_tool_spec.rb`

- verifies room type plus option-number selection
- verifies ambiguous option handling across multiple room types
- verifies room-type-only selection when exactly one visible option exists
- verifies asking for an option number when a named room type has multiple visible options
- verifies deterministic raw option parsing such as `i chose option 1`
- verifies pending-date follow-up resolution
- verifies combined room-type and date selection in one message
- verifies unique partial room-type matching
- verifies `executive one` is treated as room-type shorthand, not option one

#### `spec/services/ai_concierge_v3/tools/generate_booking_url_tool_spec.rb`

- verifies real booking quote generation returns a booking URL and expiry metadata

### Hotel Information Tools

#### `spec/services/ai_concierge_v3/tools/get_hotel_policy_tool_spec.rb`

- verifies hotel policy text is returned when present
- verifies fallback to structured property-policy data when hotel policy text is blank
- verifies the unavailable state when no policy data exists

#### `spec/services/ai_concierge_v3/tools/get_booking_context_tool_spec.rb`

- verifies structured booking rows are returned for a matching phone number
- verifies the empty booking-context state returns an empty list

#### `spec/services/ai_concierge_v3/tools/get_general_hotel_info_tool_spec.rb`

- verifies general hotel details and summary text are returned

#### `spec/services/ai_concierge_v3/tools/get_hotel_faq_tool_spec.rb`

- verifies hotel FAQ text is returned when present
- verifies the unavailable FAQ state when blank

#### `spec/services/ai_concierge_v3/tools/get_nearby_attractions_tool_spec.rb`

- verifies the full nearby-attractions list is returned

### Room Information Tools

#### `spec/services/ai_concierge_v3/tools/get_room_type_details_tool_spec.rb`

- verifies room details and amenity-name rendering for fuzzy room matches
- verifies ambiguous room-type results when multiple room types match

## Request Specs

### `spec/requests/api/v1/ai_concierge/inquiries_spec.rb`

- verifies hotel policy replies through the public API
- verifies general hotel information replies
- verifies hotel FAQ replies
- verifies nearby-attractions replies with the full attraction list
- verifies room-details replies through fuzzy room matching
- verifies ambiguous room-information follow-up prompts
- verifies timing and duration follow-up flow
- verifies unresolved `2 people` clarification flow
- verifies grouped room-type option rendering with price rows
- verifies unique date-based option selection
- verifies ambiguous date follow-up prompts with matching room type names
- verifies interrupted booking flows can resume after a hotel policy question
- verifies interrupted booking flows can resume after a room-information question
- verifies room-type-only follow-up selection when exactly one visible option exists
- verifies raw selection phrasing such as `i chose option 1`
- verifies pending-date context prevents looping on room-type follow-up
- verifies partial room-type follow-up matching
- verifies `executive one` asks for option number instead of selecting option one
- verifies `yes` returns a booking URL reply with total and expiry
- verifies `another booking` starts a fresh booking branch and does not reuse the previous selected option
- verifies hotel amenities after a completed booking returns hotel amenities instead of room-type fallback
- verifies disabled concierge returns `422`
- verifies missing `phone` and missing `prospect_public_id` returns `422`
- verifies successful responses include `prospect_public_id`
- verifies valid `prospect_public_id` continues the existing prospect conversation
- verifies invalid `prospect_public_id` returns `404`
- verifies explicit end messages end the current conversation only
- verifies a later valid inbound message reactivates ended state
- verifies booking URL generation marks the conversation ended

## Coverage Themes

- deterministic timing and duration guards
- explicit guest-count and party-split clarification
- grouped booking suggestions with stable selection metadata
- deterministic selection and ambiguity handling
- deterministic information routing across hotel policy, hotel info, nearby attractions, and room info
- hotel policy fallback from `hotel.policy` to `property_policy`
- full nearby-attractions rendering
- fuzzy room matching with ambiguity and not-found handling
- interruption and resume for paused booking flows
- confirmation before booking-link generation
- completed-branch lifecycle and fresh restart through `another booking`
- hotel/property amenities routing after completed bookings
- booking URL generation failure safety and non-completion
- phone-first prospect identity with public-ID continuation fallback
- persisted `ProspectConversationState` lifecycle metadata
- explicit current-conversation end handling and reactivation
