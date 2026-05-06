# AI Concierge V3 File Structure

## Overview

This document maps the implementation layout for `AiConciergeV3`.

- `spec.md` defines behavior and state contracts
- `research.md` explains architecture direction and product reasoning
- `tooling.md` documents the runtime tool contract, intent/topic mapping, and operator examples
- this file explains where the implementation lives

## Top-Level Flow

### `app/services/ai_concierge_v3/orchestration/inquiry_responder.rb`

- public entry point for the concierge flow
- validates readiness, normalizes request inputs, enforces prospect identity, and delegates to the turn orchestrator
- requires either `phone` or `prospect_public_id`
- returns a safe fallback payload on unexpected failures

### `app/services/ai_concierge_v3/orchestration/turn_orchestrator.rb`

- central coordinator for a single concierge turn
- resolves the hotel-scoped `Prospect` by phone first or by `prospect_public_id` fallback
- loads persisted `ProspectConversationState`, records inbound events, invokes interpretation, applies deterministic guards, merges slots, runs allowed tools, builds reply context, persists updates, and returns the final payload
- handles booking flow plus hotel-information and room-information interruptions
- reactivates ended conversation state on a later valid inbound message
- ends the current conversation for stop/bye/thanks-style messages and after booking URL generation

## Core Support Files

### `app/services/ai_concierge_v3/agents/interpreter_agent.rb`

- converts the raw user message and compact conversation summary into structured interpretation data
- classifies booking, hotel information, nearby attractions, room information, and booking context requests
- limited to interpretation only and does not own state changes or tool execution

### `app/services/ai_concierge_v3/agents/messenger_agent.rb`

- deterministic reply router for guest-facing responses
- delegates final rendering to domain-specific message builders

### `app/services/ai_concierge_v3/state/slot_merger.rb`

- merges safe user-provided slots into the active booking branch
- normalizes duration fields and clears stale downstream state when timing or guest composition changes

### `app/services/ai_concierge_v3/orchestration/transition_policy.rb`

- decides the next legal action from the current interpreted message and active branch state
- enforces end-conversation precedence, booking flow order, interruption handling, nearby-attractions replies, hotel-information replies, room-information replies, and resume behavior

### `app/services/ai_concierge_v3/state/branch_manager.rb`

- manages active, paused, resumed, and completed booking branches inside conversation state
- handles short-lived paused-flow expiry and completed-branch archival

### `app/services/ai_concierge_v3/state/state_patch_builder.rb`

- builds the normalized conversation-state patch that will be persisted after a turn
- centralizes active topic, active flow, pending question, action name, slots payload, and lifecycle metadata updates

### `app/services/ai_concierge_v3/tools/tool_registry.rb`

- exposes the deterministic tool set available to the orchestrator
- keeps tool lookup centralized rather than hard-coded across multiple files

### `app/services/ai_concierge_v3/matching/room_type_matcher.rb`

- shared room-name matcher used by room-information tools
- handles exact matching, fuzzy token matching, ambiguity, and not-found outcomes

### `app/services/ai_concierge_v3/conversation_summary_builder.rb`

- produces a compact summary of conversation state for the interpreter
- keeps the model input smaller and focused on relevant context

### `app/services/ai_concierge_v3/orchestration/response_payload_builder.rb`

- builds the final public API payload shape returned by the concierge endpoint
- includes `prospect_public_id` on successful concierge responses
- keeps response formatting separate from orchestration logic

### `app/services/ai_concierge_v3/orchestration/result.rb`

- small result object used to pass structured outcome data through the flow
- helps keep orchestrator return values consistent

## Message Builders

### `app/services/ai_concierge_v3/message_builders/base_builder.rb`

- shared formatting helpers for dates, prices, times, lists, and option groups

### `app/services/ai_concierge_v3/message_builders/booking_actions_builder.rb`

- renders booking prompts, selection replies, ambiguity replies, confirmation prompts, and booking-link replies

### `app/services/ai_concierge_v3/message_builders/hotel_info_builder.rb`

- renders hotel policy, booking context, general hotel info, hotel FAQ, and nearby attractions replies

### `app/services/ai_concierge_v3/message_builders/room_info_builder.rb`

- renders room details, ambiguous room-match replies, and room-not-found replies

### `app/services/ai_concierge_v3/message_builders/fallback_builder.rb`

- produces safe fallback responses when the normal flow cannot complete successfully
- prevents internal errors from leaking raw implementation details

## Tool Files

### Booking Tools

#### `app/services/ai_concierge_v3/tools/booking/search_booking_options_tool.rb`

- performs booking option search for the current branch inputs
- returns grouped suggestion data with room type identity, dates, price, and selection metadata

#### `app/services/ai_concierge_v3/tools/booking/select_booking_option_tool.rb`

- resolves user selection input against the current suggestion set
- handles room type matching, date matching, option number matching, ambiguity handling, and pending selection context

#### `app/services/ai_concierge_v3/tools/booking/generate_booking_url_tool.rb`

- turns a confirmed option into a real booking quote link
- returns booking URL, pricing, currency, and expiry metadata for the final guest reply

### Hotel Information Tools

#### `app/services/ai_concierge_v3/tools/hotel_information/get_hotel_policy_tool.rb`

- returns hotel policy information
- uses `hotel.policy` first and falls back to `property_policy`

#### `app/services/ai_concierge_v3/tools/hotel_information/get_booking_context_tool.rb`

- returns structured booking-context data for the current guest
- used to render existing booking context in a predictable reply format

#### `app/services/ai_concierge_v3/tools/hotel_information/get_general_hotel_info_tool.rb`

- returns general hotel details such as name, address, location, and summary text

#### `app/services/ai_concierge_v3/tools/hotel_information/get_hotel_faq_tool.rb`

- returns hotel FAQ content when provided by the hotel

#### `app/services/ai_concierge_v3/tools/hotel_information/get_nearby_attractions_tool.rb`

- returns the full nearby-attractions list for the hotel

### Room Information Tools

#### `app/services/ai_concierge_v3/tools/room_information/get_room_type_details_tool.rb`

- returns room details, occupancy, and amenity names for a matched room type
- uses the shared room matcher to resolve guest phrasing

## Schema Files

### `app/services/ai_concierge_v3/schemas/interpretation_schema.rb`

- defines the strict structure expected from the interpreter
- keeps model output shape validated before the rest of the Ruby flow uses it

## Reading Order

1. Read `docs/ai-concierge/v3/spec.md` for behavioral rules and state contracts.
2. Read `docs/ai-concierge/v3/tooling.md` for the public tool contract and intent/topic mapping.
3. Read `app/services/ai_concierge_v3/orchestration/inquiry_responder.rb` for the public entry point.
4. Read `app/services/ai_concierge_v3/orchestration/turn_orchestrator.rb` for the main request lifecycle.
5. Read `transition_policy.rb`, `slot_merger.rb`, `branch_manager.rb`, and `matching/room_type_matcher.rb` for flow control and room resolution.
6. Read `message_builders/` and `tools/` for deterministic rendering and external actions.
7. Read `research.md` if you need architecture rationale or product background.

## Boundaries

- the interpreter is responsible for structured interpretation only
- the messenger is responsible for deterministic reply routing only
- message builders are responsible for final reply text
- state changes, transition decisions, and tool execution stay in Ruby
- prospect identity is persisted through `Prospect` and `ProspectConversationState`; anonymous/incognito state is outside the current V3 contract
- `ProspectProfileFact` is not part of the current V3 state model
