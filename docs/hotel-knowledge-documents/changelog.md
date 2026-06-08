# V1.3.2 — Real-Time Embedding Status (Current)

- Added per-document Turbo Stream subscriptions to knowledge index and detail pages.
- Embedding status, chunks, retry controls, and failure details now update through Action Cable without polling.
- Added a distinct `indexing` status; generation and retries enter it immediately when enqueued, while directly-enqueued jobs ensure it is set before ingestion starts.
- The UI shows a spinner only while `indexing`, and previous embedding errors are cleared before enqueueing.
- Prevented embedding-only updates on attached PDF documents from enqueueing another generation job after completion.

## Verification
- `bundle exec rspec spec/models/hotel_knowledge_document_spec.rb spec/jobs/hotel_knowledges/generate_embeddings_job_spec.rb spec/services/hotel_knowledges spec/requests/hotel_portal/hotel_knowledge_documents_spec.rb`
- 106 examples, 0 failures

---

# V1.3.1 — AI Concierge Embedding Fallback Scope

- Clarified OpenAI embedding fallback behavior: the platform `openai_api_key` is only used for AI Concierge-enabled hotels whose configured AI provider is non-OpenAI.
- Added defensive reindex guards so AI Concierge-disabled hotels cannot trigger manual embedding generation by posting directly to category reindex routes.
- Confirmed disabled hotels do not expose manual "Generate Embeddings" / "Retry Embeddings" controls.

---

# V1.3 — Knowledge Diagnostics

## Changes
- Added `HotelKnowledgeDiagnostic` as a hotel-scoped, staff-facing diagnostic record for weak or unanswered knowledge retrieval turns.
- Diagnostics can link optionally to `Prospect` and `ProspectMessage` and retain:
  - question, intent, topic, answer mode, answer, success, source
  - routed and fallback categories
  - matched knowledge chunks, match count, and best distance
  - status: `open`, `reviewed`, `resolved`, or `dismissed`
  - suggested category: `policy`, `faq`, or `general_info`
  - metadata for producer/tool context
- Added `HotelKnowledges::DiagnosticRecorder` as the domain service; AI Concierge emits diagnostic input but does not own the diagnostic model/UI.
- Added Hotel Portal `Knowledge Diagnostics` page under the existing Knowledge sidebar group.
- Staff can filter diagnostics by status, answer mode, suggested category, and date range.
- Staff can mark diagnostics as reviewed, resolved, or dismissed.
- Added `hotel_knowledges:prune_diagnostics` to delete diagnostics older than 90 days by default.

## Files Changed
- `hotel_knowledge_diagnostic.rb` — new model with scopes and validations
- `hotel_knowledges/diagnostic_recorder.rb` — new recorder service
- `knowledge_diagnostics_controller.rb` — new hotel portal controller
- `app/views/hotel_portal/knowledge_diagnostics/` — diagnostics index/detail UI
- `shared/navigation/_hotel_sidebar.html.erb` — Knowledge Diagnostics nav item under Knowledge
- `lib/tasks/hotel_knowledges.rake` — 90-day diagnostic pruning task

## Verification
- `bundle exec rspec spec/models/hotel_knowledge_diagnostic_spec.rb spec/services/hotel_knowledges/diagnostic_recorder_spec.rb spec/requests/hotel_portal/knowledge_diagnostics_spec.rb`
- 14 examples, 0 failures

---

# V1.2 — AI Embedding Pipeline

## Changes
- Added `pdf-reader` gem for PDF text extraction
- Created `PdfParsingService` — extracts clean text from uploaded PDFs, handles blank PDFs and malformed files
- Created `ChunkingService` — section-based splitting for PDFs with fixed-token fallback; paragraph-boundary splitting for text source type with fixed-token fallback for oversized paragraphs; 64-token overlap; minimum 3-token section threshold
- Created `EmbeddingService` — wraps `RubyLLM.embed` with OpenAI `text-embedding-3-small` (1536 dimensions); per-hotel API key with `AppConfig` fallback; 20-item batch processing
- Created `KnowledgeIngestionService` — orchestrates PDF parsing → chunking → embedding → bulk chunk insert via `insert_all` → updates `embedding_status` to `"indexed"`; sets `"failed"` with `last_error` in metadata on error
- Created `GenerateEmbeddingsJob` — Solid Queue `:ai_concierge` queue; `retry_on` up to 3 attempts; inline rescue marks document as failed with error message
- Added IVFFlat vector index on `hotel_knowledge_chunks.embedding` for cosine similarity search
- Added `after_commit` auto-trigger on document create/update — enqueues `GenerateEmbeddingsJob` only when `hotel.ai_concierge_enabled?` is true
- Added `reindex` action + route to all 3 knowledge controllers for manual embedding retry
- Added "Generate Embeddings" / "Retry Embeddings" button in index Manage dropdown — visible when `ai_concierge_enabled?` and status is `pending` or `failed`
- Added same button in show page header + error message display (`last_error`) in metadata sidebar for failed documents

## Files Changed
- `Gemfile` — added `pdf-reader`
- `db/migrate/20260529104830_add_ivfflat_index_to_knowledge_chunks.rb` — new
- `app/services/hotel_knowledges/pdf_parsing_service.rb` — new
- `app/services/hotel_knowledges/chunking_service.rb` — new
- `app/services/hotel_knowledges/embedding_service.rb` — new
- `app/services/hotel_knowledges/knowledge_ingestion_service.rb` — new
- `app/jobs/hotel_knowledges/generate_embeddings_job.rb` — new
- `app/models/hotel_knowledge_document.rb` — added `after_commit` callback
- `config/routes.rb` — added `post :reindex` to 3 knowledge resources
- `app/controllers/hotel_portal/knowledge_policies_controller.rb` — added `reindex` action + helper
- `app/controllers/hotel_portal/knowledge_faqs_controller.rb` — added `reindex` action + helper
- `app/controllers/hotel_portal/knowledge_general_infos_controller.rb` — added `reindex` action + helper
- `lib/tasks/hotel_ops.rake` — replaced `migrate_knowledges` with `generate_knowledge_embeddings`; added embedding step to `clean_hotel_state_records`
- `app/views/hotel_portal/knowledge_base/_documents_table.html.erb` — added embedding retry button
- `app/views/hotel_portal/knowledge_base/show.html.erb` — added retry button + error display

## Verification
- `bundle exec rspec spec/services/hotel_knowledges/ spec/jobs/hotel_knowledges/`
- 35 examples, 0 failures
- 462 existing model + request specs, 0 failures

---

# V1.1.2 — Expandable Grid Index UI

## Changes
- Replaced duplicate per-category index table markup with a single shared partial `_documents_table.html.erb` in `knowledge_base/`
- Converted desktop index from HTML `<table>`/`<tbody>`/`<tr>` to a div-based CSS grid to eliminate dropdown clipping and cell-wrapping bugs
- Added `knowledge_row_expand_controller.js` Stimulus controller for click-to-expand row behavior showing inline content preview
- PDF documents show an "Open PDF" button in the expanded row (opens in new tab)
- FAQ Q&A pairs rendered inline in the expanded row
- Removed redundant inner card header labels (page title was repeated inside the card)
- Changed "Total N" to "N document(s)" with proper pluralization
- Compacted table padding and added `truncate` / `min-w-0` to prevent title wrapping
- Tags column now shows max 3 tags with a `+N` overflow indicator
- Fixed FAQ controller `assign_metadata_and_content` — the normalized array form is now written back to `@document.metadata["qa_pairs"]` so the database stores the correct format
- Added defensive hash-to-array normalization in index and show views for existing FAQ data stored in the old hash-key format
- Removed `overflow-hidden` from the card wrapper to allow dropdown menus to render outside the card boundary
- Managed dropdown no longer uses `data-dropdown-floating` — uses simple absolute positioning below the trigger without floating math

## Files Changed
- `app/views/hotel_portal/knowledge_base/_documents_table.html.erb` — new shared grid-based index partial
- `app/javascript/controllers/knowledge_row_expand_controller.js` — new Stimulus controller
- `app/views/hotel_portal/knowledge_policies/index.html.erb` — rewritten as thin wrapper
- `app/views/hotel_portal/knowledge_faqs/index.html.erb` — rewritten as thin wrapper
- `app/views/hotel_portal/knowledge_general_infos/index.html.erb` — rewritten as thin wrapper
- `app/controllers/hotel_portal/knowledge_faqs_controller.rb` — fixed metadata normalization
- `app/views/hotel_portal/knowledge_base/show.html.erb` — added defensive FAQ metadata rendering

## Verification
- `bundle exec rspec spec/models/hotel_knowledge_document_spec.rb spec/models/hotel_knowledge_chunk_spec.rb spec/requests/hotel_portal/hotel_knowledge_documents_spec.rb`
- 42 examples, 0 failures

---

# V1.1 — Split into 3 Resource Pages

## Changes
- Split single Knowledge Documents CRUD into 3 dedicated resource pages: Policy Management, FAQs Management, General Info Management
- Each page scoped to its category with a separate controller; category auto-set on create
- Category dropdown removed from form (category inferred from controller context)
- Shared CRUD views in `knowledge_base/` — new, edit, show, and form partial rendered by all 3 controllers
- Removed old `HotelKnowledgeDocumentsController` and its views
- Expanded sidebar "Knowledge" section with 3 children (matching Reports `<details>` pattern)
- Global search updated with 3 separate entries
- Request specs rewritten to cover all 3 controllers via shared examples
- Fixed schema.rb to properly represent `hotel_knowledge_chunks` pgvector column
- Fixed `render :edit` path in all 3 controllers to reference shared template

## Files Changed
- `app/controllers/hotel_portal/knowledge_policies_controller.rb` — new
- `app/controllers/hotel_portal/knowledge_faqs_controller.rb` — new
- `app/controllers/hotel_portal/knowledge_general_infos_controller.rb` — new
- `app/views/hotel_portal/knowledge_policies/index.html.erb` — new
- `app/views/hotel_portal/knowledge_faqs/index.html.erb` — new
- `app/views/hotel_portal/knowledge_general_infos/index.html.erb` — new
- `app/views/hotel_portal/knowledge_base/_form.html.erb` — new (shared)
- `app/views/hotel_portal/knowledge_base/new.html.erb` — new (shared)
- `app/views/hotel_portal/knowledge_base/edit.html.erb` — new (shared)
- `app/views/hotel_portal/knowledge_base/show.html.erb` — new (shared)
- `app/controllers/hotel_portal/hotel_knowledge_documents_controller.rb` — deleted
- `app/views/hotel_portal/hotel_knowledge_documents/` — deleted (5 view files)
- `config/routes.rb` — replaced 1 resource with 3
- `app/views/shared/navigation/_hotel_sidebar.html.erb` — flat link replaced with expandable section
- `app/services/hotel_portal/global_search_service.rb` — 1 entry replaced with 3
- `spec/requests/hotel_portal/hotel_knowledge_documents_spec.rb` — rewritten
- `db/schema.rb` — added missing `hotel_knowledge_chunks` table definition

---

# V1 — Data Infrastructure & Admin CRUD

## Changes
- Replaced `hotel.faq` and `hotel.policy` JSONB columns with normalized `hotel_knowledge_documents` + `hotel_knowledge_chunks` two-table structure
- Added pgvector extension for future embedding support
- Added `neighbor` gem for ActiveRecord nearest-neighbor queries
- Added Active Storage attachment on `hotel_knowledge_documents` for PDF uploads
- Consolidated FAQ/Policy admin pages into a unified Knowledge Documents CRUD
- Added Stimulus controller for source_type toggle (text vs PDF)
- Added migration rake task `hotel_ops:migrate_knowledges` for existing data
- Removed old `HotelFaqsController`, `HotelPoliciesController`, and associated views/stimulus files
- Updated sidebar and global search to point to new Knowledge Documents page

## Files Changed
- `Gemfile` — added `neighbor`
- `db/migrate/20260526062809_enable_pgvector.rb` — new
- `db/migrate/20260526062817_create_hotel_knowledge_documents.rb` — new
- `db/migrate/20260526062823_create_hotel_knowledge_chunks.rb` — new
- `db/migrate/20260526062829_remove_faq_and_policy_from_hotels.rb` — new (post-migration)
- `app/models/hotel_knowledge_document.rb` — new
- `app/models/hotel_knowledge_chunk.rb` — new
- `app/models/hotel.rb` — added `has_many :knowledge_documents`
- `app/controllers/hotel_portal/hotel_knowledge_documents_controller.rb` — new
- `app/views/hotel_portal/hotel_knowledge_documents/` — 5 view files (index, new, edit, show, _form)
- `app/javascript/controllers/knowledge_document_controller.js` — new
- `config/routes.rb` — replaced faq/policy routes with knowledge_documents resource
- `app/views/shared/navigation/_hotel_sidebar.html.erb` — updated nav link
- `app/services/hotel_portal/global_search_service.rb` — updated search entry
- `lib/tasks/hotel_ops.rake` — added `migrate_knowledges` task
- `spec/models/hotel_knowledge_document_spec.rb` — new
- `spec/models/hotel_knowledge_chunk_spec.rb` — new
- `spec/requests/hotel_portal/hotel_knowledge_documents_spec.rb` — new
- `spec/system/hotel/profile_update_spec.rb` — removed old FAQ/Policy tests
