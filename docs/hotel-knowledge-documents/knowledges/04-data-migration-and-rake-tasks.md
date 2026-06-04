# Data Migration & Rake Tasks

## Overview

Knowledge documents (`HotelKnowledgeDocument`) created through the admin UI or the old `migrate_knowledges` task start with `embedding_status: "pending"`. This rake task generates embeddings for all pending documents across all AI-concierge-enabled hotels.

## Rake Task

**File:** `lib/tasks/hotel_ops.rake`
**Task:** `hotel_ops:generate_knowledge_embeddings`

### What it does

Iterates over all hotels, skips those without AI Concierge enabled, and enqueues a `GenerateEmbeddingsJob` for each pending knowledge document:

```ruby
Hotel.find_each do |hotel|
  next unless hotel.ai_concierge_enabled?
  pending_docs = hotel.knowledge_documents.where(embedding_status: "pending")
  pending_docs.find_each do |doc|
    HotelKnowledges::GenerateEmbeddingsJob.perform_later(doc.id)
  end
end
```

### Usage

```bash
bin/rails hotel_ops:generate_knowledge_embeddings
```

### Notes
- Only processes documents with `embedding_status: "pending"` — already-indexed documents are skipped
- Skips hotels that don't have AI Concierge enabled (`hotel.ai_concierge_enabled?`)
- The job runs via Solid Queue on the `ai_concierge` queue
- The old `hotel_ops:migrate_knowledges` task (which read from removed `hotel.faq`/`hotel.policy` JSONB columns) has been removed

## Diagnostic Retention Task

**File:** `lib/tasks/hotel_knowledges.rake`
**Task:** `hotel_knowledges:prune_diagnostics`

Deletes `HotelKnowledgeDiagnostic` records older than 90 days by default.

```bash
bin/rails hotel_knowledges:prune_diagnostics
```

Override retention with `RETENTION_DAYS`:

```bash
RETENTION_DAYS=30 bin/rails hotel_knowledges:prune_diagnostics
```

## Clean State Integration

The `clean_hotel_state_records` method, called by both `hotel_ops:clean_state`
and `hotel_ops:realtime_state`, includes two knowledge document steps:

### Step 6 — Clean & Seed

Destroys all existing knowledge documents (chunks cascade via `dependent: :destroy`)
and creates 6 sample documents:

| Category | Title | Chunks | Sample Content |
|----------|-------|--------|---------------|
| FAQ | Booking & Reservations | 3 Q&A | Check-in/out times, cancellations, early check-in. Sets `metadata.qa_pairs` + concatenated `content` + one chunk per Q&A. |
| FAQ | Amenities & Services | 4 Q&A | Pool hours, Wi-Fi, spa/fitness, room service. Same structure as above. |
| FAQ | Transportation | 3 Q&A | Airport transfers, parking, shuttle service. Same structure as above. |
| Policy | Check-in & Check-out | 1 | Times, ID requirements, late check-out |
| Policy | Cancellation Policy | 1 | Free cancellation window, no-show charges |
| Policy | House Rules | 1 | Quiet hours, smoking, pets, visitors |

All seeded documents get `embedding_status: "pending"`.

### Step 7 — Embed (opt-in)

Generates embeddings for pending documents. **Opt-in** — skipped by default.
Pass `EMBED=true` to enable:

```bash
# Clean state with default sample documents (no embeddings)
bin/rails hotel_ops:clean_state['My Hotel']

# Clean state with sample documents + embeddings
EMBED=true bin/rails hotel_ops:clean_state['My Hotel']
```
