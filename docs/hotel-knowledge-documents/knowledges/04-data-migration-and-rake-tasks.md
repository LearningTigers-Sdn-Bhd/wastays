# Data Migration & Rake Tasks

## Overview

Existing `hotel.faq` and `hotel.policy` JSONB data must be migrated into the new `hotel_knowledge_documents` + `hotel_knowledge_chunks` tables. A rake task handles this.

## Rake Task

**File:** `lib/tasks/hotel_ops.rake`
**Task:** `hotel_ops:migrate_knowledges`

### What it does

Iterates over all hotels and migrates their existing data:

#### FAQ Migration
Each FAQ section → one `HotelKnowledgeDocument` (category: "faq"):
```ruby
section = { "section_name" => "General", "items" => [{ "question" => "...", "answer" => "..." }] }
# Becomes:
doc = HotelKnowledgeDocument(title: section_name, source_type: "text", category: "faq")
# Each Q&A pair becomes a chunk:
chunk = HotelKnowledgeChunk(content: "Q: {question}\nA: {answer}", chunk_index: N)
```

#### Policy Migration
Each policy item → one `HotelKnowledgeDocument` (category: "policy"):
```ruby
item = { "title" => "Cancellation", "content" => "Free cancellation up to 24 hours..." }
# Becomes:
doc = HotelKnowledgeDocument(title: item["title"], source_type: "text", category: "policy", content: "...")
chunk = HotelKnowledgeChunk(content: "...", chunk_index: 0)
```

### Usage

```bash
bin/rails hotel_ops:migrate_knowledges
```

### Notes
- All migrated documents get `embedding_status: "pending"` — embeddings must be generated separately
- All migrated documents get `tags: []` — old data had no tags
- All migrated documents get `effective_date: nil` (forever)
- The migration is idempotent but not incremental — it creates new records each time

## Post-Migration Steps

After the rake task completes successfully:

1. **Drop old columns** — run migration `20260526062829_remove_faq_and_policy_from_hotels.rb`
2. **Update `booking_snapshot`** — remove `faq`/`policy` from the exclusion list in `hotel.rb` (already done)

## Production Deployment Order

```
1. Deploy code (new tables are empty, old columns still exist)
2. Run: bin/rails hotel_ops:migrate_knowledges
3. Run: bin/rails db:migrate (applies the drop-column migration)
4. Verify: check a few hotels' knowledge documents in the admin UI
```
