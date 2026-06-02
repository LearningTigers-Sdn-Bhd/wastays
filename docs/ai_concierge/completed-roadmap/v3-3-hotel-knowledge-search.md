# V3.3 — Hotel Knowledge Search

## Context
V3.2 restored FAQ and policy tools by reading normalized `HotelKnowledgeDocument` and `HotelKnowledgeChunk` records, but answers still used whole-document concatenation. The hotel knowledge infrastructure already had embeddings and vector indexes, so AI Concierge needed query-aware retrieval and safer answer generation.

## Completed
- [x] Added `HotelKnowledges::SearchService` for vector retrieval over indexed knowledge chunks
- [x] Search filters by hotel, category, indexed document status, and non-empty embeddings
- [x] Search returns normalized internal metadata: content, document title, category, language, version, chunk index, and vector distance
- [x] Added `AiConciergeV3::Agents::KnowledgeAnswerAgent` for LLM synthesis over retrieved snippets and structured fallback facts
- [x] Added `HybridAnswerBuilder` answer-mode selection:
  - `fallback` for direct structured facts or existing full-document fallback text
  - `deterministic` for one strong retrieved match
  - `synthesized` for multiple retrieved matches
  - `unavailable` when no useful source exists
- [x] Updated policy, FAQ, and general-info tools to accept the raw guest query
- [x] Updated `LibrarianOrchestrator` to pass the message into knowledge tools
- [x] Updated `HotelInfoBuilder` to prefer the hybrid `answer` while preserving old fallback rendering
- [x] Added deterministic policy intent guarding for phrases such as `booking policy`, `hotel policies`, `rules`, `cancellation`, `check in`, and `check out`

## Outcome
- Hotel knowledge answers now use the guest question to retrieve relevant chunks instead of always returning full documents
- Source document metadata stays internal and is not shown to guests
- Booking interruptions still preserve and resume `booking_task`
- Misclassified `booking policy` phrasing is corrected to `hotel_policy` before transition routing
- No database migration required

## Verification
- `bundle exec rspec spec/services/ai_concierge_v3`
- 158 examples, 0 failures
- `bundle exec rspec spec/services/hotel_knowledges spec/jobs/hotel_knowledges spec/models/hotel_knowledge_document_spec.rb spec/models/hotel_knowledge_chunk_spec.rb`
- 50 examples, 0 failures
- `bundle exec rubocop --cache false` on touched files
