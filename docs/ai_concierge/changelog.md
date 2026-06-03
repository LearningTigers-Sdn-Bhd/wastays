# AI Concierge Changelog

## V4 — Interpreter Message-Type and Compact State Context (Current)

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
