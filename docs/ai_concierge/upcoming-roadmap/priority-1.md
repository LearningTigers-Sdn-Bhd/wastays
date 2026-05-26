# Priority 1: Top Risks

## Remaining Risks
1. interpreter invents month or date from vague booking interest
2. interpreter invents duration from month-only messages
3. interpreter converts `people` into `adults`
4. stale option sets survive corrections
5. disambiguation loops if pending selection context is not preserved
6. room-type matching is too strict for natural shorthand
7. booking-link generation fails because selected options lack `room_type_id`

## V3.1 Risks
1. interpreter fails to extract rate plan name from vague guest descriptions ("the cheaper one", "first one")
2. rate plan name normalization across providers — some hotels may use non-standard naming
3. rate plan selection during suspended booking resume may lose context

## Expansion Candidates
- hotel-policy interruption and resume (implemented — verify coverage)
- booking context rendering (implemented — verify coverage)
- correction handling (implemented — verify coverage)
- another-booking branching (implemented — verify coverage)

## Future Work
- `ProspectProfileFact` integration for persistent guest memory
- Anonymous/incognito conversation state support
- Additional information tool groups (restaurants, spa, events)
- Multi-language support
- Voice interface support

## V4 — Hotel Knowledge Tool Migration

### Context
`hotel.faq` and `hotel.policy` JSONB columns have been replaced with a normalized `hotel_knowledge_documents` + `hotel_knowledge_chunks` two-table structure (see `docs/hotel-knowledge-documents/`). The AI Concierge's `GetHotelFaqTool` and `GetHotelPolicyTool` still read from the removed JSONB columns and are currently broken.

### Required
- [ ] Update `GetHotelFaqTool` to query `HotelKnowledgeDocument.where(category: "faq")` and join chunk content
- [ ] Update `GetHotelPolicyTool` to query `HotelKnowledgeDocument.where(category: "policy")` with chunk content; keep `PropertyPolicy` fallback
- [ ] Decide chunk rendering strategy: concatenate all chunks in index order, or use vector similarity
- [ ] Update `LibrarianOrchestrator` if tool interfaces change
- [ ] Update `InterpreterAgent` prompt if intent/topic schema changes (e.g. merge hotel_faq + hotel_policy into hotel_knowledge)
- [ ] Remove old tool specs referencing `hotel.faq`/`hotel.policy` and write new ones
- [ ] Run `hotel_ops:migrate_knowledges` in production before deploying this change

### Risk
- Hotels must run the migration rake task before this change deploys, otherwise the old data is gone and the new tables are empty
- Tool interface changes could ripple through `MessageBuilders` and reply rendering
