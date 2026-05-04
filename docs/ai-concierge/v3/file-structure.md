# AI Concierge V3 File Structure

## Overview

This document maps the implementation layout for `AiConciergeV3`.

- `spec.md` defines behavior and state contracts
- `research.md` explains architecture direction and product reasoning
- this file explains where the implementation lives

## Top-Level Flow

### `app/services/ai_concierge_v3/inquiry_responder.rb`

- public entry point for the concierge flow
- validates readiness, normalizes request inputs, resolves identity mode, and delegates to the turn orchestrator
- returns a safe fallback payload on unexpected failures

### `app/services/ai_concierge_v3/turn_orchestrator.rb`

- central coordinator for a single concierge turn
- loads conversation state, records inbound events, invokes interpretation, applies deterministic guards, merges slots, runs allowed tools, builds reply context, persists updates, and returns the final payload

## Core Support Files

### `app/services/ai_concierge_v3/interpreter_agent.rb`

- converts the raw user message and compact conversation summary into structured interpretation data
- limited to interpretation only and does not own state changes or tool execution

### `app/services/ai_concierge_v3/messenger_agent.rb`

- renders deterministic guest-facing replies from structured reply context
- formats option lists, confirmation prompts, hotel policy replies, and booking context replies

### `app/services/ai_concierge_v3/slot_merger.rb`

- merges safe user-provided slots into the active booking branch
- normalizes duration fields and clears stale downstream state when timing or guest composition changes

### `app/services/ai_concierge_v3/transition_policy.rb`

- decides the next legal action from the current interpreted message and active branch state
- enforces the booking flow order for timing, duration, guest clarification, selection, confirmation, interruption, and resume

### `app/services/ai_concierge_v3/branch_manager.rb`

- manages active, paused, resumed, and completed booking branches inside conversation state
- handles short-lived paused-flow expiry and completed-branch archival

### `app/services/ai_concierge_v3/state_patch_builder.rb`

- builds the normalized conversation-state patch that will be persisted after a turn
- centralizes active topic, active flow, pending question, action name, and slots payload updates

### `app/services/ai_concierge_v3/tool_registry.rb`

- exposes the deterministic tool set available to the orchestrator
- keeps tool lookup centralized rather than hard-coded across multiple files

### `app/services/ai_concierge_v3/conversation_summary_builder.rb`

- produces a compact summary of conversation state for the interpreter
- keeps the model input smaller and focused on relevant context

### `app/services/ai_concierge_v3/response_payload_builder.rb`

- builds the final public API payload shape returned by the concierge endpoint
- keeps response formatting separate from orchestration logic

### `app/services/ai_concierge_v3/fallback_builder.rb`

- produces safe fallback responses when the normal flow cannot complete successfully
- prevents internal errors from leaking raw implementation details

### `app/services/ai_concierge_v3/result.rb`

- small result object used to pass structured outcome data through the flow
- helps keep orchestrator return values consistent

## Tool Files

### `app/services/ai_concierge_v3/tools/search_booking_options_tool.rb`

- performs booking option search for the current branch inputs
- returns grouped suggestion data with room type identity, dates, price, and selection metadata

### `app/services/ai_concierge_v3/tools/select_booking_option_tool.rb`

- resolves user selection input against the current suggestion set
- handles room type matching, date matching, option number matching, ambiguity handling, and pending selection context

### `app/services/ai_concierge_v3/tools/generate_booking_url_tool.rb`

- turns a confirmed option into a real booking quote link
- returns booking URL, pricing, currency, and expiry metadata for the final guest reply

### `app/services/ai_concierge_v3/tools/get_hotel_policy_tool.rb`

- returns structured hotel policy data for deterministic policy replies
- used when the guest asks policy questions during or outside the booking flow

### `app/services/ai_concierge_v3/tools/get_booking_context_tool.rb`

- returns structured booking-context data for the current guest
- used to render existing booking context in a predictable reply format

## Schema Files

### `app/services/ai_concierge_v3/schemas/interpretation_schema.rb`

- defines the strict structure expected from the interpreter
- keeps model output shape validated before the rest of the Ruby flow uses it

## Reading Order

1. Read `docs/ai-concierge/v3/spec.md` for behavioral rules and state contracts.
2. Read `app/services/ai_concierge_v3/inquiry_responder.rb` for the public entry point.
3. Read `app/services/ai_concierge_v3/turn_orchestrator.rb` for the main request lifecycle.
4. Read `transition_policy.rb`, `slot_merger.rb`, and `branch_manager.rb` for state and flow control.
5. Read `messenger_agent.rb` and the files under `tools/` for deterministic output and external actions.
6. Read `research.md` if you need architecture rationale or product background.

## Boundaries

- the interpreter is responsible for structured interpretation only
- the messenger is responsible for deterministic reply rendering only
- state changes, transition decisions, and tool execution stay in Ruby
