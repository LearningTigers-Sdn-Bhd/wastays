# V3.2 — Hotel Knowledge Tool Migration

## Context
`hotel.faq` and `hotel.policy` JSONB columns were replaced with a normalized `hotel_knowledge_documents` + `hotel_knowledge_chunks` two-table structure (see `docs/hotel-knowledge-documents/`). The AI Concierge's `GetHotelFaqTool` and `GetHotelPolicyTool` still read from the removed JSONB columns and were broken.

## Completed
- [x] Updated `GetHotelFaqTool` to query `HotelKnowledgeDocument.where(category: "faq")` and join chunk content
- [x] Updated `GetHotelPolicyTool` to query `HotelKnowledgeDocument.where(category: "policy")` with chunk content; kept `PropertyPolicy` fallback
- [x] Chunk rendering strategy: concatenate all chunks in index order
- [x] No `LibrarianOrchestrator` changes needed — tool interfaces unchanged
- [x] No `InterpreterAgent` changes needed — intent/topic schema unchanged
- [x] Removed old tool specs referencing `hotel.faq`/`hotel.policy` and wrote new ones

## Outcome
- All 13 tool specs passing
- Output contracts preserved — no ripples through `MessageBuilders` or reply rendering
- Hotel knowledge documents created in V1+ infrastructure now served by AI Concierge tools
