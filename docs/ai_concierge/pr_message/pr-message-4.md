# Implement live embedding updates on hotel knowledge management pages

## Brief Background

Hotel knowledge embedding generation runs in a background job, but the management pages previously required a manual refresh to show status changes, generated chunks, or failure details. The UI also used `pending` for both documents waiting to be generated and documents actively being processed, which made it unclear when generation was actually running.

## Solution

- Added a distinct embedding lifecycle:
  - `pending` for documents ready to generate
  - `indexing` while generation is queued or running
  - `indexed` after successful generation
  - `failed` after an error
- Added per-document Turbo Stream subscriptions to hotel knowledge index and detail pages.
- Broadcasts a Turbo morph refresh when embedding status or error metadata changes.
- Shows a live spinner while a document is `indexing`.
- Shows Generate Embeddings only for `pending` documents and Retry Embeddings only for `failed` documents.
- Updates status badges, chunks, controls, and failure details through Action Cable without polling.
- Centralized manual generation and retry behavior so documents enter `indexing`, clear previous errors, and enqueue the embedding job consistently.
- Prevented embedding-only updates on attached PDF documents from accidentally enqueueing another generation job.
- Updated hotel knowledge lifecycle and embedding pipeline documentation.

## Notable Files

- `app/models/hotel_knowledge_document.rb`
- `app/jobs/hotel_knowledges/generate_embeddings_job.rb`
- `app/controllers/hotel_portal/knowledge_policies_controller.rb`
- `app/controllers/hotel_portal/knowledge_faqs_controller.rb`
- `app/controllers/hotel_portal/knowledge_general_infos_controller.rb`
- `app/views/hotel_portal/knowledge_base/_documents_table.html.erb`
- `app/views/hotel_portal/knowledge_base/show.html.erb`
- `spec/models/hotel_knowledge_document_spec.rb`
- `spec/jobs/hotel_knowledges/generate_embeddings_job_spec.rb`
- `spec/requests/hotel_portal/hotel_knowledge_documents_spec.rb`
- `docs/hotel-knowledge-documents/`

## Verification

- `bundle exec rspec spec/models/hotel_knowledge_document_spec.rb spec/jobs/hotel_knowledges/generate_embeddings_job_spec.rb spec/services/hotel_knowledges spec/requests/hotel_portal/hotel_knowledge_documents_spec.rb`
- 106 examples, 0 failures
- `bundle exec rubocop app/models/hotel_knowledge_document.rb app/jobs/hotel_knowledges/generate_embeddings_job.rb app/controllers/hotel_portal/knowledge_policies_controller.rb app/controllers/hotel_portal/knowledge_faqs_controller.rb app/controllers/hotel_portal/knowledge_general_infos_controller.rb spec/models/hotel_knowledge_document_spec.rb spec/jobs/hotel_knowledges/generate_embeddings_job_spec.rb spec/requests/hotel_portal/hotel_knowledge_documents_spec.rb`
- 8 files inspected, no offenses detected

## Risk Notes

- Turbo updates require Action Cable and the background job worker to be running in the deployed environment.
- The `indexing` state is stored in the existing string column, so no database migration is required.
- If a worker stops after a document enters `indexing`, the document remains in that state until generation is retried or operational recovery updates it.
