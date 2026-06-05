# V4.4 — Orchestrator Policy Extraction and Booking Search Query Proof

## Problem

`TurnOrchestrator` and `BookingOrchestrator` had accumulated several decision clusters that were important but not core orchestration responsibilities: conversation-control phrasing, booking-ready revision detection, and rate-plan matching. `SearchBookingOptionsTool` already preloaded availability and rates, but there was no regression proof that query count stayed bounded as room types and rate plans grew.

## Changes

- Extracted `AiConcierge::Orchestration::BookingRevisionPolicy` for booking-ready `change rate` and `change room` decisions.
- Extracted `AiConcierge::Matching::RatePlanMatcher` for deterministic rate-plan matching.
- Extracted `AiConcierge::Orchestration::Core::ConversationControlPolicy` for booking-attempt cancellation, explicit end requests, end-confirmation replies, and end-confirmation mode.
- Kept orchestrators as coordinators:
  - `TurnOrchestrator` still owns lifecycle sequencing, persistence, and response construction.
  - `BookingOrchestrator` still owns booking flow execution and delegates matching/revision decisions.
- Optimized `SearchBookingOptionsTool` to load ordered room types once and use date-indexed preloaded inventory/rate maps.
- Added spec-local SQL query counting with `ActiveSupport::Notifications` to prove booking option search query count remains bounded as room types and rate plans grow.

## Public Contract

No public API, schema, route, or guest-facing copy changed.

Inquiry responses remain:

- `reply_message`
- `needs_human_support`
- `action_name`
- `prospect_public_id`

## Verification

- `bundle exec rspec spec/services/ai_concierge/orchestration spec/services/ai_concierge/matching spec/services/ai_concierge/tools/booking/search_booking_options_tool_spec.rb`
- `bundle exec rspec spec/requests/api/v1/ai_concierge`
- `bundle exec rubocop --cache false app/services/ai_concierge spec/services/ai_concierge spec/requests/api/v1/ai_concierge`
