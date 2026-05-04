# AI Concierge V3 Tests

## Overview

This document maps the current test surface for `AiConciergeV3`.

- `spec.md` defines behavior and state contracts
- this file explains which specs cover those behaviors

## How To Read The Suite

1. Start with `spec/requests/api/v1/ai_concierge/inquiries_spec.rb` for end-to-end concierge behavior.
2. Read `turn_orchestrator_spec.rb`, `transition_policy_spec.rb`, and `slot_merger_spec.rb` for core flow control.
3. Read the tool specs under `spec/services/ai_concierge_v3/tools/` for isolated booking logic.
4. Read `messenger_agent_spec.rb` for deterministic guest-facing reply formatting.

## Service Specs

### `spec/services/ai_concierge_v3/inquiry_responder_spec.rb`

- verifies disabled-concierge failure behavior
- verifies successful delegation for hotels with concierge enabled

### `spec/services/ai_concierge_v3/turn_orchestrator_spec.rb`

- verifies the top-level deterministic guard flow
- covers duration-first handling for month-window requests
- covers rejecting invented timing for vague booking messages
- covers preserving `2 people` as unresolved until adult and child split is clarified

### `spec/services/ai_concierge_v3/slot_merger_spec.rb`

- verifies follow-up resolution from `2 people` to `adults`
- verifies stale downstream state is cleared when timing changes
- verifies derived `nights` and `check_out` from `days` and `check_in`

### `spec/services/ai_concierge_v3/transition_policy_spec.rb`

- verifies the legal next-action order for booking timing, duration, guest count, adult count, and party split
- verifies search becomes available only after timing, duration, and guest split are resolved
- verifies paused booking flows resume before validating selection-like follow-ups

### `spec/services/ai_concierge_v3/branch_manager_spec.rb`

- verifies the active booking branch can be paused and resumed

### `spec/services/ai_concierge_v3/state_patch_builder_spec.rb`

- verifies `paused_flows` and `completed_booking_branches` are normalized in persisted slots payload

### `spec/services/ai_concierge_v3/interpreter_agent_spec.rb`

- verifies schema-shaped interpretation output for booking timing and total guest count extraction

### `spec/services/ai_concierge_v3/messenger_agent_spec.rb`

- verifies deterministic greeting formatting
- verifies grouped room-type option rendering with price formatting
- verifies narrowed room-type option prompts
- verifies confirmation formatting with `*Yes*` and `*No*`
- verifies hotel policy block formatting
- verifies structured booking-context rendering for present and empty states

## Tool Specs

### `spec/services/ai_concierge_v3/tools/search_booking_options_tool_spec.rb`

- verifies grouped booking options include room type identity, positions, and selection IDs

### `spec/services/ai_concierge_v3/tools/select_booking_option_tool_spec.rb`

- verifies room type plus option-number selection
- verifies ambiguous option handling across multiple room types
- verifies room-type-only selection when exactly one visible option exists
- verifies asking for an option number when a named room type has multiple visible options
- verifies deterministic raw option parsing such as `i chose option 1`
- verifies pending-date follow-up resolution
- verifies combined room-type and date selection in one message
- verifies unique partial room-type matching
- verifies `executive one` is treated as room-type shorthand, not option one

### `spec/services/ai_concierge_v3/tools/generate_booking_url_tool_spec.rb`

- verifies real booking quote generation returns a booking URL and expiry metadata

### `spec/services/ai_concierge_v3/tools/get_hotel_policy_tool_spec.rb`

- verifies structured hotel policy facts are returned from property policy data

### `spec/services/ai_concierge_v3/tools/get_booking_context_tool_spec.rb`

- verifies structured booking rows are returned for a matching phone number
- verifies the empty booking-context state returns an empty list

## Request Specs

### `spec/requests/api/v1/ai_concierge/inquiries_spec.rb`

- verifies hotel policy replies through the public API
- verifies timing and duration follow-up flow
- verifies unresolved `2 people` clarification flow
- verifies grouped room-type option rendering with price rows
- verifies unique date-based option selection
- verifies ambiguous date follow-up prompts with matching room type names
- verifies interrupted booking flows can resume after a hotel policy question
- verifies room-type-only follow-up selection when exactly one visible option exists
- verifies raw selection phrasing such as `i chose option 1`
- verifies pending-date context prevents looping on room-type follow-up
- verifies partial room-type follow-up matching
- verifies `executive one` asks for option number instead of selecting option one
- verifies `yes` returns a booking URL reply with total and expiry
- verifies `another booking` starts a fresh booking branch and does not reuse the previous selected option
- verifies disabled concierge returns `422`

## Coverage Themes

- deterministic timing and duration guards
- explicit guest-count and party-split clarification
- grouped booking suggestions with stable selection metadata
- deterministic selection and ambiguity handling
- interruption and resume for paused booking flows
- confirmation before booking-link generation
- completed-branch lifecycle and fresh restart through `another booking`
