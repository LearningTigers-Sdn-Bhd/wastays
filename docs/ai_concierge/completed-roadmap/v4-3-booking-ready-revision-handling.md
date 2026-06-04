# V4.3 — Booking-Ready Revision Handling

## Context

When a booking branch already had enough information to quote or confirm, guest phrasing like `change rate` or `change room` could be ambiguous with broader correction/cancellation handling. The concierge needed deterministic revision behavior that preserves valid upstream booking context while only clearing the downstream state that became stale.

## Changes

- Added booking-ready revision handling in `BookingOrchestrator` before normal booking action resolution.
- Rate revisions preserve the selected room/date option, clear selected rate-plan state and confirmation candidate, and re-ask rate-plan selection when multiple rates exist.
- Single-rate selected options re-ask confirmation without cancelling or clearing upstream booking context.
- Option revisions preserve timing, duration, guest composition, room count, and suggested options while clearing selected option, rate-plan state, pending selection, and confirmation candidate.
- Same-turn option revisions can resolve the new room/date option immediately, then continue to rate-plan selection or confirmation.
- Revision handling also applies after suspended hotel-information interruptions resume.
- Explicit cancellation remains separate; `changed my mind` still resets the booking task while `change room` and `change rate` do not.

## Verification

- `bundle exec rspec spec/services/ai_concierge_v3/orchestration/booking_orchestrator_spec.rb`
- `bundle exec rspec spec/services/ai_concierge_v3/state/slot_merger_spec.rb`
- `bundle exec rspec spec/requests/api/v1/ai_concierge/rate_plan_black_box_spec.rb`
- `bundle exec rspec spec/requests/api/v1/ai_concierge/inquiries_spec.rb`
- `bundle exec rspec spec/services/ai_concierge_v3`
- `bundle exec rubocop --cache false app/services/ai_concierge_v3 spec/services/ai_concierge_v3 spec/requests/api/v1/ai_concierge`
