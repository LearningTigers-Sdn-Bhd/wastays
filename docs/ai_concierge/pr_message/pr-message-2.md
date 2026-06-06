# Enhance AI Concierge: knowledge search, booking hardening, and orchestration cleanup

## Brief Background

This branch turns the AI Concierge from a V3 booking/info prototype into a more production-ready conversation system. The work adds normalized hotel knowledge documents with vector search, migrates AI Concierge knowledge tools onto that retrieval path, hardens multi-turn booking behavior, and reorganizes the orchestration code into focused domains.

The public inquiry API remains stable:

- `reply_message`
- `needs_human_support`
- `action_name`
- `prospect_public_id`

## TLDR

- Added hotel knowledge documents, chunks, embedding jobs, admin pages, and diagnostics.
- Migrated FAQ, policy, and general-info answers to hybrid knowledge retrieval.
- Improved AI Concierge interpretation with internal `message_type` classification and compact state summaries.
- Hardened booking selection, rate-plan choice, booking URL generation, interruptions, cancellations, and booking-ready revisions.
- Split orchestration into `core`, `conversation`, `booking`, and `hotel_knowledge` domains.
- Renamed the internal namespace from `AiConciergeV3` to `AiConcierge` while preserving API routes and payload shape.
- Added broad service and request coverage for booking, hotel knowledge, rate plans, diagnostics, and orchestration behavior.

## Solution

### Hotel Knowledge Documents

- Added normalized `HotelKnowledgeDocument` and `HotelKnowledgeChunk` models.
- Added `pgvector`/`neighbor` support for chunk-level similarity search.
- Added PDF/text ingestion services, chunking, embedding generation, and reindex tasks.
- Replaced the old hotel FAQ/policy edit screens with category-specific knowledge admin pages:
  - policies
  - FAQs
  - general info
- Added staff-facing knowledge diagnostics to surface weak or unanswered AI Concierge knowledge turns.

### Hybrid Hotel Knowledge Retrieval

- Migrated AI Concierge policy, FAQ, and general-info tools to query knowledge documents.
- Added query-aware hybrid answer building:
  - routed category search first
  - cross-category retry across `general_info`, `faq`, and `policy`
  - structured fallback when indexed content is missing
- Added `KnowledgeAnswerAgent` for synthesized answers from multiple retrieved matches.
- Kept source titles, matches, and diagnostics metadata internal so guest replies stay clean.
- Hardened black-box routing so misplaced hotel content can still answer likely guest questions.

### Conversation Interpretation and State

- Added internal interpreter `message_type` classification before intent/topic routing.
- Switched interpreter context toward compact conversation summaries instead of full chat history.
- Added deterministic Ruby guards for hotel information intent and booking slot normalization.
- Preserved the core rule that the LLM interprets structured meaning, while Ruby owns state changes, transition decisions, tool execution, and final reply rendering.

### Booking Flow Hardening

- Added deterministic rate-plan matching for:
  - ordinals such as `first one`
  - cheapest/lowest price intent
  - exact and partial names
  - `standard`
  - refundable vs non-refundable wording
- Improved room-type matching with aliases, reordered shorthand, plural/suffix normalization, and small typo tolerance.
- Hardened booking URL generation with selected-option validation and safe internal error codes.
- Ensured failed booking URL generation does not complete or end the conversation.
- Cleared stale downstream booking state when timing, duration, party composition, or room count changes.
- Added natural booking-attempt cancellation phrases without conflating them with ending the whole conversation.
- Added suspended booking resume behavior after hotel information interruptions.

### Booking-Ready Revisions

- Added scoped revision handling for guests who already reached quote confirmation:
  - `change rate` / `show rates again` preserves selected room/date and reopens rate-plan choice.
  - `change room` / `different option` preserves timing, duration, guest composition, room count, and suggested options while clearing downstream selection state.
  - Same-turn room revisions such as `change room to Deluxe Room option 1` can resolve immediately.
- Kept explicit cancellation separate from booking revision language.

### Orchestration Refactor

- Reorganized AI Concierge service code into focused domains:
  - `orchestration/core`
  - `orchestration/conversation`
  - `orchestration/booking`
  - `orchestration/hotel_knowledge`
- Kept `TurnOrchestrator` as the high-level coordinator.
- Extracted conversation lifecycle, control handling, interpretation prep, response persistence, booking handlers, hotel-knowledge routing, diagnostics, and reply mapping into focused collaborators.
- Consolidated RubyLLM setup in `AiConcierge::Providers::RubyLlmClient`.
- Renamed the internal namespace from `AiConciergeV3` to `AiConcierge`.

## Notable Files

### AI Concierge

- `app/services/ai_concierge/orchestration/core/inquiry_responder.rb`
- `app/services/ai_concierge/orchestration/turn_orchestrator.rb`
- `app/services/ai_concierge/orchestration/conversation/`
- `app/services/ai_concierge/orchestration/booking/`
- `app/services/ai_concierge/orchestration/hotel_knowledge/`
- `app/services/ai_concierge/agents/interpreter_agent.rb`
- `app/services/ai_concierge/agents/knowledge_answer_agent.rb`
- `app/services/ai_concierge/matching/rate_plan_matcher.rb`
- `app/services/ai_concierge/matching/room_type_matcher.rb`
- `app/services/ai_concierge/tools/hotel_information/hybrid_answer_builder.rb`

### Hotel Knowledge

- `app/models/hotel_knowledge_document.rb`
- `app/models/hotel_knowledge_chunk.rb`
- `app/models/hotel_knowledge_diagnostic.rb`
- `app/services/hotel_knowledges/knowledge_ingestion_service.rb`
- `app/services/hotel_knowledges/search_service.rb`
- `app/services/hotel_knowledges/embedding_service.rb`
- `app/services/hotel_knowledges/diagnostic_recorder.rb`
- `app/controllers/hotel_portal/knowledge_*_controllers.rb`
- `app/views/hotel_portal/knowledge_base/`
- `app/views/hotel_portal/knowledge_diagnostics/index.html.erb`

### Docs and Coverage

- `docs/ai_concierge/changelog.md`
- `docs/ai_concierge/knowledges/`
- `docs/ai_concierge/test-cases/`
- `docs/hotel-knowledge-documents/`
- `spec/services/ai_concierge/`
- `spec/requests/api/v1/ai_concierge/`
- `spec/services/hotel_knowledges/`
- `spec/requests/hotel_portal/knowledge_diagnostics_spec.rb`
- `spec/requests/hotel_portal/hotel_knowledge_documents_spec.rb`

## Verification

Documented verification from the feature changelog:

- `bundle exec rspec spec/services/ai_concierge spec/requests/api/v1/ai_concierge`
- 307 examples, 0 failures
- `bundle exec rubocop --cache false app/services/ai_concierge spec/services/ai_concierge spec/requests/api/v1/ai_concierge`
- no offenses

Earlier branch checkpoints also covered:

- hotel knowledge models, ingestion, embedding, search, diagnostics, and portal request specs
- AI Concierge request-level black-box booking and rate-plan conversations
- booking URL generation, option selection, room/rate matching, state merging, and orchestration policies

## Risk Notes

- Retrieval quality still depends on hotels maintaining useful knowledge content.
- Hotel-specific room/rate naming may still need future synonym configuration for unusual provider names.
- The interpreter `message_type` is internal guidance only; Ruby guards remain the final authority for transitions and state changes.
- Public API behavior should remain stable because route, params, and response payload shape were intentionally preserved.
