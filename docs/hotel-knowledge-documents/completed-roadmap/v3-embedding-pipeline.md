# V3.2 — AI Embedding Pipeline

## Completed
- `pdf-reader` gem added for PDF text extraction
- `PdfParsingService` — takes file path, extracts text via `pdf-reader`, cleans noise (page numbers, form feeds, extra whitespace), raises `PdfParsingError` on blank text
- `ChunkingService` — accepts text + source type; PDF uses section-based split (`\n{2,}`) with fixed-token fallback (~512 tokens, 64-token overlap); text uses paragraph-boundary split with fixed-token fallback for oversized single paragraphs; discards sub-3-token fragments; returns array of `{ content:, chunk_index: }`
- `EmbeddingService` — wraps `RubyLLM.embed` with OpenAI `text-embedding-3-small` (1536 dims); configures per-hotel API key via `RubyLLM.context`; falls back to `AppConfig.get("openai_api_key")` when hotel's provider isn't OpenAI; batches in groups of 20; raises `EmbeddingError` on API failure
- `KnowledgeIngestionService` — orchestrates: PDF → `PdfParsingService` + `ChunkingService`, text → `ChunkingService` → `EmbeddingService` → `insert_all` bulk insert → `embedding_status: "indexed"`; on error: sets `"failed"` and stores error in `metadata.last_error`; transactionally replaces existing chunks
- `GenerateEmbeddingsJob` — Solid Queue `:ai_concierge` queue; `retry_on HotelKnowledges::IngestionError, attempts: 3`; inline rescue marks document as failed; `discard_on ActiveJob::DeserializationError`; uses `find_by` for graceful missing-document handling
- IVFFlat index on `hotel_knowledge_chunks.embedding` using `vector_cosine_ops`
- Auto-trigger `after_commit` on create/update — only fires when `hotel.ai_concierge_enabled?` is true
- Manual `reindex` action on all 3 category controllers with `post` route
- "Generate Embeddings" / "Retry Embeddings" button in index Manage dropdown (visible when `ai_concierge_enabled?` and status `pending`/`failed`)
- Same button in show page header + `metadata.last_error` display in metadata sidebar for failed status
- 35 service + job specs; 462 existing model + request specs — all green

## Key Design Decisions
| Decision | Choice |
|----------|--------|
| Embedding model | OpenAI `text-embedding-3-small` (1536d) |
| Embedding client | `RubyLLM.embed` (reuses existing gem) |
| API key fallback | hotel's key if provider is OpenAI → `AppConfig.get("openai_api_key")` |
| Chunk size | ~512 tokens with 64-token overlap |
| Vector index | IVFFlat with `vector_cosine_ops` |
| Queue | `:ai_concierge` (Solid Queue) |
| Auto-trigger guard | `hotel.ai_concierge_enabled?` |
| PDF parser | `pdf-reader` v2.15 |
