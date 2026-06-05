# Later Priority 2 (Implemented in V1.2)

> All items below were implemented as part of **V1.2 — AI Embedding Pipeline**. See `completed-roadmap/v1-embedding-pipeline.md` and `knowledges/05-embeddings-pipeline.md`.

---

## Archived Design Specs (for reference)

### 1. PdfParsingService
Single responsibility: file → clean text

Takes a file path
Extracts text via pdf-reader
Cleans noise (page numbers, extra whitespace, form feeds)
Returns a plain string
If text is blank, marks document as failed with a clear error message

### 2. PdfChunkingService → ChunkingService (merged)
Single responsibility: clean text → array of string chunks

Takes the clean text string from PdfParsingService
Tries section-based splitting first (headings, double newlines, Q&A patterns)
Falls back to fixed token split if a section is too large
Discards chunks that are too short to be meaningful
Returns plain array of strings

### 3. EmbeddingService
Single responsibility: text → vectors

Takes a single string or array of strings
Calls OpenAI text-embedding-3-small
Returns a single vector or array of vectors
Handles batching so you don't hit API limits

### 4. KnowledgeIngestionService
Single responsibility: orchestrates the full pipeline

Takes a HotelKnowledgeDocument record
Calls PdfParsingService → ChunkingService → EmbeddingService
Bulk inserts chunks via insert_all
Updates document status to indexed on success, failed on error with error message in metadata
