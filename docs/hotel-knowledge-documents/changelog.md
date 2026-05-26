# V1.1.2 — Expandable Grid Index UI (Current)

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
