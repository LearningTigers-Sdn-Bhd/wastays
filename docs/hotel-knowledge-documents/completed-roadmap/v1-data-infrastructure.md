# V1 — Data Infrastructure & Admin CRUD

## Completed
- Two-table schema design (`hotel_knowledge_documents` + `hotel_knowledge_chunks`) with pgvector support
- `HotelKnowledgeDocument` model with validations, Active Storage attachment, and chunk lifecycle
- `HotelKnowledgeChunk` model with `has_neighbors :embedding` for future vector search
- Migration rake task `hotel_ops:migrate_knowledges` to move existing `hotel.faq`/`hotel.policy` JSONB data
- Unified Knowledge Documents admin CRUD replacing separate FAQ and Policy pages
- Stimulus controller for source_type toggle (textarea vs PDF file upload)
- Sidebar, routes, and global search updated
- Old FAQ/Policy controllers, views, and stimulus files removed
- Post-deploy drop-column migration for `hotels.faq` and `hotels.policy`
- Model specs (validations, associations, defaults, cascading deletes)
- Request specs (full CRUD, validation errors, PDF source types)
