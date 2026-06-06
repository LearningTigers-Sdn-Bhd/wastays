# V4.2: Knowledge Diagnostics Producer and Rate-Plan Coverage

## Summary

AI Concierge now emits diagnostic input for weak or unanswered hotel knowledge turns, while diagnostics themselves live in the Hotel Knowledge domain. Rate-plan work in this release focuses on fixture-driven black-box conversation coverage and a small deterministic `cheaper` price-intent hardening found by that coverage.

## Completed

- [x] Call `HotelKnowledges::DiagnosticRecorder` after librarian tool execution for knowledge intents.
- [x] Preserve the public inquiry response payload shape.
- [x] Keep diagnostic persistence, portal UI, status workflow, and retention task under Hotel Knowledge.
- [x] Record searched and fallback category metadata internally for hybrid hotel knowledge answers.
- [x] Add request-level regressions for knowledge misses and strong deterministic answers.
- [x] Add scripted rate-plan conversation coverage for ordinal, cheapest, refundable, ambiguous, suspended-resume, confirmation, and correction scenarios.
- [x] Fix suspended rate-plan resume to process the restored branch.
- [x] Treat `cheaper` as deterministic price intent before ordinal matching.

## Verification

- `bundle exec rspec spec/models/hotel_knowledge_diagnostic_spec.rb spec/services/hotel_knowledges/diagnostic_recorder_spec.rb spec/requests/hotel_portal/knowledge_diagnostics_spec.rb spec/requests/api/v1/ai_concierge/rate_plan_black_box_spec.rb`
- 21 examples, 0 failures
