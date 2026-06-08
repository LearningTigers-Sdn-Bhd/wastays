# Refactor AI embedding fallback for hotel knowledge

## Brief Background

Hotel knowledge embeddings were already generated through OpenAI `text-embedding-3-small`, even when a hotel's AI Concierge chat provider was not OpenAI. The intended behavior is narrower: only AI Concierge-enabled hotels can generate knowledge embeddings, and the platform `openai_api_key` should only be a fallback for those enabled hotels using a non-OpenAI provider.

AI Concierge-disabled hotels should not auto-index, should not see manual indexing controls, and should not be able to trigger indexing through direct reindex route posts.

## Solution

- Scoped `HotelKnowledges::EmbeddingService` to AI Concierge-enabled hotels.
- Preserved the OpenAI key priority:
  - OpenAI AI Concierge provider uses the hotel's encrypted AI provider key.
  - Non-OpenAI AI Concierge providers use `AppConfig.get("openai_api_key")` for embeddings.
  - Missing platform OpenAI key raises the existing embedding error path.
- Added defensive guards to all category reindex actions:
  - policies
  - FAQs
  - general info
- Preserved existing UI and rake behavior:
  - Manual indexing controls remain hidden for AI Concierge-disabled hotels.
  - Auto-indexing remains gated by `hotel.ai_concierge_enabled?`.
  - `demo:embeddings` continues skipping disabled hotels.
- Updated hotel knowledge docs and changelog as `V1.3.1`.

## Notable Files

- `app/services/hotel_knowledges/embedding_service.rb`
- `app/controllers/hotel_portal/knowledge_policies_controller.rb`
- `app/controllers/hotel_portal/knowledge_faqs_controller.rb`
- `app/controllers/hotel_portal/knowledge_general_infos_controller.rb`
- `spec/services/hotel_knowledges/embedding_service_spec.rb`
- `spec/requests/hotel_portal/hotel_knowledge_documents_spec.rb`
- `docs/hotel-knowledge-documents/changelog.md`
- `docs/hotel-knowledge-documents/knowledges/05-embeddings-pipeline.md`
- `docs/hotel-knowledge-documents/knowledges/04-data-migration-and-rake-tasks.md`

## Verification

- `bundle exec rspec spec/services/hotel_knowledges/embedding_service_spec.rb spec/requests/hotel_portal/hotel_knowledge_documents_spec.rb spec/models/hotel_knowledge_document_spec.rb`
- 58 examples, 0 failures
- `bundle exec rubocop app/services/hotel_knowledges/embedding_service.rb app/controllers/hotel_portal/knowledge_faqs_controller.rb app/controllers/hotel_portal/knowledge_policies_controller.rb app/controllers/hotel_portal/knowledge_general_infos_controller.rb spec/services/hotel_knowledges/embedding_service_spec.rb spec/requests/hotel_portal/hotel_knowledge_documents_spec.rb`
- 6 files inspected, no offenses detected

## Risk Notes

- Non-OpenAI AI Concierge hotels require the platform `openai_api_key` to be configured before embeddings can be generated.
- Direct reindex posts for AI Concierge-disabled hotels now redirect without enqueueing jobs.
- This does not enable guest-facing AI Concierge for disabled hotels and does not introduce schema changes.
