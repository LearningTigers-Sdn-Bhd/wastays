# Embeddings Pipeline

## Overview

The embedding pipeline processes knowledge documents into vector embeddings for semantic search. Implemented in V1.2.

## Architecture

```
document created/updated
    │
    ▼ (after_commit if hotel.ai_concierge_enabled?)
GenerateEmbeddingsJob
    │
    ▼
KnowledgeIngestionService
    │
    ├── PDF → PdfParsingService → clean text → ChunkingService
    │                    ↓ (no text) → embedding_status: "failed"
    │
    └── Text → ChunkingService
                    │
                    ▼
              ChunkingService
                    │
                    ├── source_type: "pdf" → section-based split (⏎⏎)
                    │   └── oversized sections → fixed-token split (~512 tokens, 64 overlap)
                    │
                    └── source_type: "text" → paragraph split (⏎⏎)
                        └── oversized single paragraph → fixed-token split
                         |
                         ▼
                    Array of { content:, chunk_index: }
                         |
                         ▼
                   EmbeddingService
                         |
                         ├── RubyLLM.embed via hotel API key (or AppConfig fallback)
                         ├── Model: text-embedding-3-small (1536 dims)
                         └── Batches of 20
                         |
                         ▼
                   Bulk insert via insert_all
                         |
                         ▼
                   embedding_status = "indexed"
```

## Chunking Strategy

The chunking approach depends on the document source type and content structure:

### PDF Source Type

| PDF Type | Strategy | Fallback |
|----------|----------|---------|
| Structured policy/FAQ doc | Section-based parsing (`\n{2,}`) | Fixed 512-token split |
| Unstructured prose | Fixed 512-token split only | — |

Sections with fewer than 3 tokens are discarded as noise.

### Text Source Type
- Manual entries are single-chunk by default (if ≤512 tokens)
- Long content (>512 tokens) is split on paragraph boundaries (`\n{2,}`)
- Oversized single paragraphs fall back to fixed 512-token split
- 64-token overlap applied in fixed-token splits

## Services

### PdfParsingService
```
PdfParsingService.new(file_path).call → clean_text_string
```
- Uses `pdf-reader` gem
- Removes page numbers, form feeds, extra whitespace
- Raises `PdfParsingError` if no extractable text

### ChunkingService
```
ChunkingService.new(text, source_type: "text").call → [{ content:, chunk_index: }]
```
- Source-type-aware splitting strategy
- Returns empty array for blank text

### EmbeddingService
```
EmbeddingService.new(hotel:).call(texts) → [[float] * 1536, ...]
```
- Configures RubyLLM with per-hotel context
- API key priority: hotel's OpenAI key → `AppConfig.get("openai_api_key")`
- Returns array of 1536-dimensional vectors

### KnowledgeIngestionService
```
KnowledgeIngestionService.new(document).call → chunks_collection
```
- Orchestrates the full pipeline
- Handles errors: sets `embedding_status: "failed"`, stores `last_error` in metadata
- Transactionally replaces existing chunks

## Background Job

```ruby
class HotelKnowledges::GenerateEmbeddingsJob < ApplicationJob
  queue_as :ai_concierge
  # retry_on HotelKnowledges::IngestionError, attempts: 3
  # inline rescue marks document as failed
  # discard_on ActiveJob::DeserializationError
end
```

### Triggering

| Event | Action | Guard |
|-------|--------|-------|
| Document created (text) | `after_commit` enqueues job | `hotel.ai_concierge_enabled?` |
| Document created (pdf) | `after_commit` enqueues job | `hotel.ai_concierge_enabled?` |
| Document updated (content change) | `after_commit` enqueues job | `hotel.ai_concierge_enabled?` |
| Embedding failed | Manual "Retry Embeddings" button in UI | `hotel.ai_concierge_enabled?` + status `failed` |
| Embedding pending | Manual "Generate Embeddings" button in UI | `hotel.ai_concierge_enabled?` + status `pending` |

## Vector Index

```ruby
add_index :hotel_knowledge_chunks, :embedding,
  using: :ivfflat,
  opclass: :vector_cosine_ops
```

## Query Pattern

```ruby
# Cosine similarity search:
query_vector = EmbeddingService.new(hotel:).call([query_text]).first
results = HotelKnowledgeChunk.nearest_neighbors(:embedding, query_vector, distance: "cosine").limit(5)
```

## Error Handling

- `PdfParsingError` / `EmbeddingError` / `IngestionError` all propagate to the job
- Job's `retry_on` handles up to 3 retries, then marks document `"failed"`
- Job's inline `rescue` immediately marks document `"failed"` and stores the error message
- Metadata sidebar in show view displays `last_error` for failed documents
- Admin can manually retry any `failed` or `pending` document via the UI button
