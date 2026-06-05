# V1.3: Knowledge Diagnostics

## Summary

Knowledge Diagnostics adds a staff-facing review queue for weak or unanswered hotel knowledge retrieval turns. AI Concierge can produce diagnostics, but the storage, UI, workflow, and retention behavior belong to the Hotel Knowledge feature domain.

## Completed

- [x] Added `HotelKnowledgeDiagnostic` scoped to hotel with optional prospect and prospect message links.
- [x] Added `HotelKnowledges::DiagnosticRecorder` for generic knowledge diagnostic persistence.
- [x] Added Hotel Portal `KnowledgeDiagnosticsController` and index UI.
- [x] Added Knowledge Diagnostics to the existing sidebar Knowledge group.
- [x] Added filters for status, answer mode, suggested category, and date range.
- [x] Added status updates for reviewed, resolved, and dismissed diagnostics.
- [x] Added `hotel_knowledges:prune_diagnostics` with 90-day default retention.
- [x] Added model, service, and portal request specs.

## Verification

- `bundle exec rspec spec/models/hotel_knowledge_diagnostic_spec.rb spec/services/hotel_knowledges/diagnostic_recorder_spec.rb spec/requests/hotel_portal/knowledge_diagnostics_spec.rb`
- 14 examples, 0 failures
