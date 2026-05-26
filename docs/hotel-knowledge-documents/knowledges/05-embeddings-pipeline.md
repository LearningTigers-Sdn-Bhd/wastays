# Embeddings Pipeline (Planned)

## Overview

This document describes the planned embedding pipeline for Phase 2. Nothing is implemented yet.

## Chunking Strategy

The chunking approach depends on the document source type and content structure:

### PDF Source Type

| PDF Type | Strategy | Fallback |
|----------|----------|---------|
| Structured policy/FAQ doc | Section-based parsing | Fixed token size |
| Scanned image | OCR via tesseract-ocr | Same pipeline |
| Data table (rates, packages) | Extract as markdown table, keep whole table as one chunk | — |
| Unstructured prose | Fixed token size only | — |

### Text Source Type
- Manual entries are single-chunk by default
- Long content (>512 tokens) should be split on paragraph boundaries with overlap

## Embedding Generation

```ruby
# Example (not implemented):
class GenerateEmbeddingsJob < ApplicationJob
  queue_as :ai_concierge

  def perform(document_id)
    document = HotelKnowledgeDocument.find(document_id)
    document.chunks.each do |chunk|
      embedding = EmbeddingClient.generate(chunk.content)
      chunk.update!(embedding: embedding, token_count: count_tokens(chunk.content))
    end
    document.update!(embedding_status: "indexed")
  rescue => e
    document.update!(embedding_status: "failed")
    raise e
  end
end
```

### Provider Considerations
- Embedding dimension (1536) matches OpenAI's `text-embedding-3-small`
- Should be configurable per hotel, similar to LLM provider config
- Batch generation for efficiency

## Vector Index

After embeddings are populated, create an index:

```ruby
add_index :hotel_knowledge_chunks, :embedding,
  using: :ivfflat,
  opclass: :vector_cosine_ops
```

## Query Pattern

```ruby
# Cosine similarity search (future):
chunk = HotelKnowledgeChunk.nearest_neighbors(:embedding, query_embedding, distance: "cosine").limit(5)
```

## Triggering

| Event | Action |
|-------|--------|
| Document created (source_type: text) | Generate embeddings synchronously or via job |
| Document created (source_type: pdf) | Parse PDF → chunk → generate embeddings (job) |
| Document updated | Increment version, regenerate chunks + embeddings |
| Embedding failed | Set status to `failed`, retry via admin action |
