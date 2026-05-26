# Priority 1 — Embedding Pipeline & Tool Migration

## Remaining Risks
1. Old AI Concierge info tools (`GetHotelFaqTool`, `GetHotelPolicyTool`) still read from removed JSONB columns — broken until migrated
2. No chunking service implemented yet for PDF uploads (OCR, section-based, fixed-token fallback)
3. No embedding generation pipeline (background job, provider choice, chunk size strategy)
4. No vector index created on `hotel_knowledge_chunks.embedding` (needs IVFFlat or HNSW after embeddings are populated)
5. `effective_date` filtering not implemented in any query layer
6. Version increment logic not wired (updating a document should bump version and regenerate chunks/embeddings)

## AI Concierge Tool Migration (Blocking)
- Update `GetHotelFaqTool` to query `HotelKnowledgeDocument.where(category: "faq")` with chunk content
- Update `GetHotelPolicyTool` to query `HotelKnowledgeDocument.where(category: "policy")` with chunk content; keep `PropertyPolicy` fallback
- Decide chunk rendering strategy: join all chunks in order, or use vector similarity query
- Update `LibrarianOrchestrator` if tool interfaces change
- Update `InterpreterAgent` prompt if intent/topic schema changes
- Remove old tool specs referencing `hotel.faq`/`hotel.policy` and write new ones

## Expansion Candidates
- Automatic embedding generation on document create/update via background job
- PDF parsing pipeline: OCR (tesseract-ocr), section-based chunking, fixed-token fallback
- Vector search endpoint for AI Concierge to retrieve relevant chunks by semantic similarity
- Chunk inspection in admin UI (preview tokens, regenerate single chunk)
- Bulk import from CSV/JSON for migrating large knowledge bases
- Multi-language support per chunk (metadata tracking)

## Future Work
- Tag-based filtering for knowledge retrieval
- Effective date range queries (e.g. "only show policies active in May 2026")
- Document version history and diff view in admin UI
- `general_info` category tool integration (currently unused by AI Concierge)
- Audit logging for knowledge document changes
