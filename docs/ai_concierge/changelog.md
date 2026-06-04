# AI Concierge Changelog

## V5.0 — Orchestration Domain Restructure (Current)

### Changes
- Reorganized AI Concierge V3 orchestration into focused folders:
  - `orchestration/core` for shared entry/result/policy/payload primitives
  - `orchestration/conversation` for prospect session loading, interpretation, control handling, booking-context handling, and response persistence
  - `orchestration/booking` for booking-specific orchestration, selection, rate-plan, resume, completion, revision, and normalization logic
  - `orchestration/hotel_knowledge` for policy/general info/FAQ/attractions/room-information coordination
- Kept `TurnOrchestrator` as the top-level conversation coordinator while moving lifecycle details into focused conversation collaborators.
- Replaced `LibrarianOrchestrator` with `HotelKnowledge::Orchestrator` and extracted tool routing, state handling, diagnostics, and room reply mapping.
- Grouped shared orchestration primitives under `AiConciergeV3::Orchestration::Core`:
  - `InquiryResponder`
  - `Result`
  - `ResponsePayloadBuilder`
  - `TransitionPolicy`
  - `ConversationControlPolicy`
  - `InformationIntentGuard`
- Added same-prospect turn serialization through the conversation session loader while preserving optimistic-lock conflict handling as a fallback.
- Consolidated RubyLLM setup in `Providers::RubyLlmClient` and updated AI agents to share provider/model setup.
- Preserved public inquiry response shape:
  - `reply_message`
  - `needs_human_support`
  - `action_name`
  - `prospect_public_id`

### Files Changed
- `orchestration/turn_orchestrator.rb` — remains the high-level router over conversation, booking, hotel knowledge, and booking-context flows
- `orchestration/core/` — shared orchestration entrypoint, result envelope, policies, guards, and public payload builder
- `orchestration/conversation/` — turn/session lifecycle helpers and response persistence
- `orchestration/booking/` — booking orchestration and focused booking sub-flow handlers
- `orchestration/hotel_knowledge/` — hotel-knowledge orchestration and focused knowledge collaborators
- `providers/ruby_llm_client.rb` — shared RubyLLM provider/model/chat setup for AI agents
- lifecycle docs — updated architecture, state-transition, and implementation reading order references

### Verification
- `bundle exec rspec spec/services/ai_concierge_v3 spec/requests/api/v1/ai_concierge`
- 307 examples, 0 failures
- `bundle exec rubocop --cache false app/services/ai_concierge_v3 spec/services/ai_concierge_v3 spec/requests/api/v1/ai_concierge`
- no offenses

---

## V4.4 — Orchestrator Policy Extraction and Booking Search Query Proof

### Changes
- Extracted booking-ready revision detection out of `BookingOrchestrator` into `BookingRevisionPolicy`.
- Extracted deterministic rate-plan matching out of `BookingOrchestrator` into `RatePlanMatcher`.
- Extracted conversation-control decisions out of `TurnOrchestrator` into `ConversationControlPolicy`.
- Kept the public inquiry response unchanged:
  - `reply_message`
  - `needs_human_support`
  - `action_name`
  - `prospect_public_id`
- Optimized `SearchBookingOptionsTool` internals without changing its output:
  - ordered room types are loaded once and reused
  - preloaded inventories are indexed by room type and date
  - preloaded rates are indexed by room type and date while preserving eager-loaded rate plans
  - repeated availability checks use indexed in-memory lookup instead of repeated array scans
- Added SQL query-count regression coverage proving booking option search remains bounded as room types and rate plans grow.

### Files Changed
- `booking_revision_policy.rb` — owns booking-ready `change rate` / `change room` decision rules
- `rate_plan_matcher.rb` — owns deterministic rate-plan selection by price intent, ordinal, exact/partial name, `standard`, and refundable/non-refundable phrasing
- `conversation_control_policy.rb` — owns booking-attempt cancellation, explicit end requests, end-confirmation replies, and end-confirmation mode
- `booking_orchestrator.rb` and `turn_orchestrator.rb` — delegate policy/matching decisions while preserving orchestration responsibilities
- `search_booking_options_tool.rb` — reuses loaded room types and date-indexed inventory/rate preload maps
- policy, matcher, and booking search specs — focused unit coverage plus bounded SQL query-count regression coverage

### Verification
- `bundle exec rspec spec/services/ai_concierge_v3/orchestration spec/services/ai_concierge_v3/matching spec/services/ai_concierge_v3/tools/booking/search_booking_options_tool_spec.rb`
- 132 examples, 0 failures
- `bundle exec rspec spec/requests/api/v1/ai_concierge`
- 48 examples, 0 failures
- `bundle exec rubocop --cache false app/services/ai_concierge_v3 spec/services/ai_concierge_v3 spec/requests/api/v1/ai_concierge`
- no offenses

---

## V4.3 — Booking-Ready Revision Handling

### Changes
- Added deterministic booking-ready revision handling for guests who want to revise an active quote candidate without cancelling the booking attempt.
- `change rate` / `show rates again` now preserves the selected room/date option, clears selected rate-plan state and confirmation candidate, and re-asks the rate-plan question when multiple rates are available.
- Single-rate selected options re-ask confirmation instead of cancelling or clearing upstream booking context.
- `change room` / `different option` now preserves timing, duration, guest composition, room count, and suggested options while clearing selected option, selected rate-plan fields, pending selection, and confirmation candidate.
- Same-turn room changes such as `change room to Deluxe Room option 1` can resolve the new option immediately, then continue to rate-plan selection or confirmation.
- Revision handling also applies after a suspended hotel-information interruption resumes.
- Explicit booking-attempt cancellation remains separate; natural abandonment phrases such as `changed my mind` still reset the booking task.

### Files Changed
- `booking_orchestrator.rb` — detects booking-ready rate/option revision messages before normal booking action resolution and applies scoped downstream clearing
- `booking_orchestrator_spec.rb` — service-level coverage for rate revision, single-rate revision, room revision, and same-turn option revision
- `rate_plan_black_box_spec.rb` — request-level coverage for rate revision through quote confirmation, room revision after hotel-info interruption, cancellation, and confirmation rejection

### Verification
- `bundle exec rspec spec/services/ai_concierge_v3/orchestration/booking_orchestrator_spec.rb`
- `bundle exec rspec spec/services/ai_concierge_v3/state/slot_merger_spec.rb`
- `bundle exec rspec spec/requests/api/v1/ai_concierge/rate_plan_black_box_spec.rb`
- `bundle exec rspec spec/requests/api/v1/ai_concierge/inquiries_spec.rb`
- `bundle exec rspec spec/services/ai_concierge_v3`
- `bundle exec rubocop --cache false app/services/ai_concierge_v3 spec/services/ai_concierge_v3 spec/requests/api/v1/ai_concierge`

---

## V4.2 — Knowledge Diagnostics Producer and Rate-Plan Black-Box Coverage

### Changes
- Added AI Concierge as a producer for hotel knowledge diagnostics without moving diagnostics into the AI Concierge domain.
- Knowledge-related librarian turns now pass internal result metadata to `HotelKnowledges::DiagnosticRecorder` after tool execution.
- Guest-facing inquiry responses remain unchanged:
  - `reply_message`
  - `needs_human_support`
  - `action_name`
  - `prospect_public_id`
- Added request-level regression coverage for weak/unanswered knowledge turns creating `HotelKnowledgeDiagnostic` records.
- Added strong-answer regression coverage to avoid noisy diagnostics for deterministic retrieved knowledge.
- Added fixture-driven black-box rate-plan conversation coverage for:
  - ordinal selections such as `first one`
  - unique cheapest selections
  - suspended booking resume after a hotel-info interruption
  - `refundable` not selecting `Non-Refundable Rate`
  - ambiguous `standard` re-asking the rate-plan question
  - selected rate plan surviving into the confirmation candidate
  - selected rate plan clearing after date correction
- Hardened price-intent matching so `the cheaper one` is treated as price intent before the word `one` can be interpreted as an ordinal.

### Files Changed
- `librarian_orchestrator.rb` — records knowledge diagnostics after knowledge tool execution
- `hybrid_answer_builder.rb` and hotel information tools — include searched/fallback category metadata internally
- `booking_orchestrator.rb` — uses the restored branch during suspended rate-plan resume and recognizes `cheaper`
- `inquiries_spec.rb` — request-level knowledge diagnostic regressions
- `rate_plan_black_box_spec.rb` — scripted end-to-end rate-plan conversation scenarios

### Verification
- `bundle exec rspec spec/models/hotel_knowledge_diagnostic_spec.rb spec/services/hotel_knowledges/diagnostic_recorder_spec.rb spec/requests/hotel_portal/knowledge_diagnostics_spec.rb spec/requests/api/v1/ai_concierge/rate_plan_black_box_spec.rb`
- 21 examples, 0 failures

---

## V4.1 — Booking Hardening and Natural Follow-ups

### Changes
- Hardened booking URL generation:
  - validates confirmed option shape before quote creation
  - returns safe internal `error_code` values for missing IDs, invalid dates, quote creation failure, and missing quote records
  - preserves the public inquiry payload shape and keeps failed booking URL generation from completing or ending the conversation
- Improved room-type matching for room info and booking option selection:
  - supports reordered room-name shorthand such as `king ocean`
  - supports common aliases such as `exec`, `dlx`, `std`, and `apt`
  - handles simple plural/suffix variants and small typos
  - keeps ambiguity-first behavior when multiple room types remain plausible
- Improved rate-plan selection:
  - supports ordinal replies such as `first` and `second`
  - supports price intent such as `cheapest` and `lowest`
  - distinguishes `refundable` from `non-refundable`
  - re-asks for the rate plan when partial provider/rate names remain ambiguous
- Expanded stale downstream cleanup:
  - selected rate-plan fields are cleared with stale suggestions, pending selections, confirmation candidates, and selected options
  - compact interpreter summaries no longer expose stale shown options, rate plans, or selected-option summaries after downstream state is cleared
- Broadened booking-attempt cancellation:
  - natural phrases such as `forget the room`, `changed my mind`, and `drop the reservation` clear the booking attempt when a booking is active
  - ending the whole conversation remains separate from cancelling the booking attempt
- Fixed direct fallback responses from booking orchestration to include `prospect_public_id`.

### Files Changed
- `generate_booking_url_tool.rb` — defensive selected-option validation and internal error codes
- `room_type_matcher.rb` — scoring-based room-name matching with aliases, suffix handling, and small typo tolerance
- `select_booking_option_tool.rb` — reused stronger room-name matching for shown booking options
- `booking_orchestrator.rb` — deterministic rate-plan resolver for ordinals, price intent, refundable/non-refundable, and ambiguous partials
- `slot_merger.rb` — clears selected rate-plan fields with downstream state
- `turn_orchestrator.rb` — broader booking-attempt cancellation and stable direct fallback payloads

### Verification
- `bundle exec rspec spec/services/ai_concierge_v3`
- 200 examples, 0 failures
- `bundle exec rspec spec/requests/api/v1/ai_concierge/inquiries_spec.rb`
- 35 examples, 0 failures
- `bundle exec rubocop --cache false app/services/ai_concierge_v3 spec/services/ai_concierge_v3 spec/requests/api/v1/ai_concierge/inquiries_spec.rb`
- no offenses

---

## V4 — Interpreter Message-Type and Compact State Context

### Changes
- Added internal interpreter `message_type` classification before existing `intent`, `topic`, slots, and tool hints
- Supported internal message types:
  - `booking_request`
  - `booking_selection`
  - `booking_confirmation`
  - `hotel_info_question`
  - `hotel_policy_question`
  - `room_info_question`
  - `existing_booking_question`
  - `conversation_control`
  - `greeting_or_unknown`
- Kept the public API response unchanged:
  - `reply_message`
  - `needs_human_support`
  - `action_name`
  - `prospect_public_id`
- Enhanced compact interpreter state instead of loading full conversation history:
  - latest assistant question
  - compact shown booking options
  - compact rate-plan options
  - selected option summary
- Improved booking-vs-hotel-knowledge filtering:
  - hotel service/policy/advice questions stay in librarian routing
  - room description questions stay room info
  - date/month booking requests stay booking flow
  - yes/no and option-number replies depend on pending question/state
- Added relative-month guardrails:
  - `late this month` resolves against the current month
  - bare `this month` does not reuse stale `early/mid/late`; it asks for a date or assumption range
- Fixed suspended booking interruptions so hotel information/policy questions do not resume stale no-option searches
- Fixed booking attempt cancellation:
  - cancel-attempt phrases clear the booking task
  - guest is asked whether to start a new booking, ask hotel policies/information, or end the conversation
  - a follow-up generic booking request starts fresh instead of continuing stale state
- Accepted nested `inquiry` / `ai_concierge` request payloads and avoided unpermitted route-param noise

### Files Changed
- `interpreter_agent.rb` — message-type-first prompt and examples
- `interpretation_schema.rb` — validates supported internal `message_type`
- `conversation_summary_builder.rb` — compact context for latest assistant question, shown options, rate plans, and selected option
- `booking_input_normalizer.rb` — deterministic relative-month handling and stale segment clearing
- `information_intent_guard.rb` — booking-advice and hotel-service routing corrections
- `transition_policy.rb` — prevents hotel knowledge interruptions from resuming stale booking flow
- `turn_orchestrator.rb` — cancel-attempt reset/next-step flow and fresh booking after stale attempts
- `conversation_task_manager.rb` — booking task reset helper
- `booking_actions_builder.rb` — cancel-attempt next-step reply
- `inquiries_controller.rb` — permitted nested inquiry params

### Verification
- `bundle exec rspec spec/services/ai_concierge_v3`
- 185 examples, 0 failures
- `bundle exec rspec spec/requests/api/v1/ai_concierge/inquiries_spec.rb`
- 34 examples, 0 failures

---

## V3.4 — Black-Box Hotel Knowledge Routing

### Changes
- Treat hotel knowledge categories (`policy`, `faq`, `general_info`) as storage categories, not strict intent boundaries
- Broadened `InformationIntentGuard` so hotel knowledge questions do not accidentally start booking slot collection:
  - policy/rules/house rules/cancellation/check-in/check-out -> `hotel_policy`
  - parking, transportation, airport transfer, shuttle, WiFi, breakfast, restaurant, spa, pool, amenities, and facilities -> `hotel_information`
- Preserved clear booking requests, including room availability and booking/date phrasing, as booking flow
- Added cross-category retrieval fallback in `HybridAnswerBuilder`:
  - first search the routed category
  - if no useful answer is found, retry across `general_info`, `faq`, and `policy`
  - only then use structured fallback or unavailable answer
- Preserved booking interruption/resume semantics for guarded hotel knowledge turns

### Files Changed
- `information_intent_guard.rb` — broader deterministic hotel-knowledge guard and booking contrast rules
- `hybrid_answer_builder.rb` — cross-category hotel knowledge fallback before generic structured fallback
- `interpreter_agent.rb` — prompt examples for house rules, transportation, and parking

### Verification
- `bundle exec rspec spec/services/ai_concierge_v3`
- 170 examples, 0 failures
- `bundle exec rubocop --cache false ...`
- no offenses

---

## V3.3 — Hotel Knowledge Search

### Changes
- Added query-aware vector retrieval with `HotelKnowledges::SearchService`
- Added hybrid hotel knowledge answer selection:
  - deterministic answers for direct structured facts and single strong matches
  - LLM synthesis for multi-snippet knowledge answers
  - unavailable fallback when no useful knowledge source exists
- Added `KnowledgeAnswerAgent` for grounded synthesis using retrieved snippets and structured hotel facts only
- Updated policy, FAQ, and general-info tools to accept the guest message as `query`
- Knowledge tools now return `answer`, `answer_mode`, `source`, and internal `knowledge_matches`
- `HotelInfoBuilder` prefers hybrid `answer` while preserving legacy fallback rendering
- Added deterministic policy routing guard for `booking policy`, policies/rules, cancellation, check-in, and check-out phrasing
- Preserved booking interruption/resume behavior; policy/info turns still suspend active booking when appropriate

### Files Changed
- `app/services/hotel_knowledges/search_service.rb` — new vector retrieval service
- `knowledge_answer_agent.rb` — new LLM synthesis agent
- `hybrid_answer_builder.rb` — new answer-mode selector
- `get_hotel_policy_tool.rb`, `get_hotel_faq_tool.rb`, `get_general_hotel_info_tool.rb` — query-aware hybrid answers
- `librarian_orchestrator.rb` — passes raw message to knowledge tools
- `hotel_info_builder.rb` — prefers `answer`
- `information_intent_guard.rb` and `interpreter_agent.rb` — policy phrasing guard/prompt examples

### Verification
- `bundle exec rspec spec/services/ai_concierge_v3`
- 158 examples, 0 failures
- `bundle exec rubocop --cache false ...`
- no offenses

---

## V3.2 — Hotel Knowledge Tool Migration

### Changes
- Migrated `GetHotelFaqTool` to query `HotelKnowledgeDocument.where(category: "faq")` with chunk content instead of the removed `hotel.faq` JSONB column
- Migrated `GetHotelPolicyTool` to query `HotelKnowledgeDocument.where(category: "policy")` with chunk content instead of the removed `hotel.policy` JSONB column
- Preserved `PropertyPolicy` fallback for structured policy fields (check-in/out times, cancellation policy)
- Chunk rendering strategy: all chunks joined in `chunk_index` order per document
- No changes needed to `LibrarianOrchestrator`, `ToolRegistry`, or `InterpreterAgent` — tool interfaces unchanged

### Files Changed
- `get_hotel_faq_tool.rb` — rewritten to query `HotelKnowledgeDocument` + `HotelKnowledgeChunk`
- `get_hotel_policy_tool.rb` — rewritten to query `HotelKnowledgeDocument` + `HotelKnowledgeChunk`
- `get_hotel_faq_tool_spec.rb` — rewritten with knowledge document factories
- `get_hotel_policy_tool_spec.rb` — rewritten with knowledge document factories
- `spec/factories/hotel_knowledge_chunks.rb` — new factory

### Verification
- `bundle exec rspec spec/services/ai_concierge_v3/tools/hotel_information/`
- 13 examples, 0 failures

---

## V3.1 — Rate Plan Selection

### Changes
- Search results now return all rate plans per option (Standard Rate, Non-Refundable, etc.) instead of only the cheapest
- Options rendered in nested format: date option → sub-items for each rate plan with name and price
- New `rate_plan_selection` state between option selection and confirmation when multiple rate plans exist
- Interpreter extracts `rate_plan_name` slot when guest picks a rate plan
- Fuzzy matching for rate plan names (supports "the cheaper one", "standard", "non-refundable")
- `GenerateBookingUrlTool` and `CreateQuote` pass `rate_plan_id` so quotes use the selected plan's pricing
- Single-plan options auto-select and skip the rate plan step (backward compatible)
- Options without `rate_plans` field (legacy state) render in original format

### Files Changed
- `search_booking_options_tool.rb` — options carry `rate_plans` array per option
- `base_builder.rb` — nested rendering in `option_group_lines`
- `slot_merger.rb`, `conversation_task_manager.rb` — `selected_rate_plan_id/name` fields, `waiting_for_rate_plan_selection` state
- `interpreter_agent.rb` — `rate_plan_name` slot in schema and prompt
- `booking_orchestrator.rb` — `ask_rate_plan` / `rate_plan_selection` sub-step, `find_matching_rate_plan`
- `booking_actions_builder.rb` — `ask_rate_plan` message, updated `ask_confirmation` to show selected rate plan price
- `generate_booking_url_tool.rb`, `create_quote.rb`, `availability_service.rb` — `rate_plan_id` forwarding

## V3 — Initial Release


### Architecture Decisions
- Hybrid architecture: LLM handles structured interpretation only; Ruby handles state, transitions, validation, tool execution, and reply rendering
- Deterministic guest-facing replies (not model-generated)
- `ProspectConversationState` as durable state container
- V2 task-state normalization on read (`state_version: 2`)
- Legacy `active` and `paused_flows` read once and converted, not written back

### Product Decisions
- `2 people` triggers clarification (not assumed `adults=2`)
- Option selection requires confirmation before booking URL generation
- Completed booking branches live only in short-lived conversation state
- Month-window requests require duration before search
- Final booking reply includes: booking URL, total amount, expiry
- Hotel/property amenities routing corrected by `InformationIntentGuard`

### Implemented Features
- Booking timing/duration/guest-count collection
- Grouped room-type option suggestions with prices
- Option selection with ambiguity handling
- Confirmation before booking URL generation
- Hotel policy, general hotel info, FAQ, nearby attractions, room information
- Booking context lookup
- Interruption and resume for suspended booking flows
- Correction handling (change of month/window, party composition)
- Multiple booking branches (`another booking`)
- Public ID continuation for phone-less follow-ups
- Explicit end-conversation handling and state reactivation
- Booking URL generation failure safety
- Date alignment algorithm for consistent option windows
- Fuzzy room-type matching with ambiguity and not-found handling
- Smart party split suggestion with remainder
- Pure digit extraction for guest counts
- Raw option number phrase acceptance
- Abandonment priority fixing selection loop bug
