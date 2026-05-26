# Architecture Overview

## Design Decision

Replaced two JSONB columns (`hotel.faq`, `hotel.policy`) on the `hotels` table with a normalized two-table structure. This enables:

- Per-document metadata (language, tags, version, effective date)
- Active Storage file attachments for PDF uploads
- Chunk-level granularity for embedding/vector search
- Extensible category system (policy, faq, general_info) beyond the original two types

## Two-Table Design

### `hotel_knowledge_documents`
Represents a single knowledge document — either manually entered text or an uploaded PDF.

- Scoped to a hotel
- Has one Active Storage attachment (for PDF source type)
- Has many chunks (destroyed on document delete)
- Tracks embedding generation status: `pending` → `indexed` | `failed`

### `hotel_knowledge_chunks`
Represents a single content segment of a document with an optional vector embedding.

- Belongs to a document
- Ordered by `chunk_index`
- `embedding` column uses `vector(1536)` for OpenAI-compatible embedding dimensions
- `has_neighbors :embedding` via the `neighbor` gem for cosine similarity search

## Category System

| Category | Purpose | AI Concierge Tool |
|----------|---------|-------------------|
| `policy` | Operational policies (check-in, cancellation, house rules) | `GetHotelPolicyTool` |
| `faq` | Frequently asked questions | `GetHotelFaqTool` |
| `general_info` | General hotel facts, amenities, descriptions | `GetGeneralHotelInfoTool` |

## Source Types

| Source | Storage | Content |
|--------|---------|---------|
| `text` | `content` column on document | Manually entered via textarea |
| `pdf` | Active Storage attachment | Uploaded file, parsed into chunks later |

## Embedding Lifecycle

```
document created → embedding_status: "pending"
                         ↓
    (background job) generate embeddings per chunk
                         ↓
              success → "indexed"
              failure → "failed"
```

## Relationship to AI Concierge

The AI Concierge info tools (`GetHotelFaqTool`, `GetHotelPolicyTool`) are designed to query these tables instead of the old JSONB columns. The migration is tracked in `docs/ai_concierge/upcoming-roadmap/priority-1.md`.
