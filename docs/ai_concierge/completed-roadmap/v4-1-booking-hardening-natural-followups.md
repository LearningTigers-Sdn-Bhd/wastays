# V4.1: Booking Hardening and Natural Follow-ups

## Problem

V4 improved routing and compact state context, but several production-risk edges remained:

- confirmed booking options could be stale or malformed before quote generation
- room-type matching was still strict for natural shorthand, reordered words, aliases, and minor typos
- rate-plan selection depended too much on simple name matching
- stale selected options and rate-plan summaries could remain after upstream booking changes
- booking-attempt cancellation only recognized explicit cancel-attempt wording

## Completed Work

- [x] Added defensive validation to `GenerateBookingUrlTool` before calling `BookingEngine::CreateQuote`
- [x] Returned safe internal `error_code` values for malformed selections and quote failures while preserving guest-facing fallback behavior
- [x] Kept failed booking URL generation from archiving booking state or ending the conversation
- [x] Added stronger deterministic room-type matching:
  - alias support (`exec`, `dlx`, `std`, `apt`)
  - token reordering (`king ocean`)
  - suffix/plural normalization
  - small typo tolerance
- [x] Reused stronger room-name matching in booking option selection
- [x] Added deterministic rate-plan resolution for:
  - ordinal replies (`first`, `second`)
  - price intent (`cheapest`, `lowest`)
  - `standard`
  - `refundable` vs `non-refundable`
  - ambiguous partial matches that should re-ask instead of guessing
- [x] Cleared `selected_rate_plan_id` and `selected_rate_plan_name` with downstream booking state
- [x] Verified compact summaries do not expose stale shown options, rate-plan options, or selected-option summaries after cleanup
- [x] Expanded booking-attempt cancellation to natural phrases such as `forget the room`, `changed my mind`, and `drop the reservation`
- [x] Preserved separation between cancelling a booking attempt and ending the whole conversation
- [x] Ensured direct fallback payloads still include `prospect_public_id`

## Key Behavior

- stale confirmed option without required quote inputs -> safe human-support fallback, booking remains uncompleted
- `king ocean` -> can match `Ocean Villa King`
- `excutive penthouse` -> can match `Executive Penthouse`
- `the cheapest one` while rate plans are shown -> selects the lowest-priced unique rate plan
- `refundable` does not select `Non-Refundable Rate`
- ambiguous rate-plan names such as `standard` with multiple standard-like plans -> re-ask rate plan
- timing or party changes clear shown options, selected options, confirmation candidates, pending selections, and selected rate-plan fields
- `forget the room` during an active booking -> cancels the booking attempt, keeps the conversation active, and asks the next step

## Verification

- `bundle exec rspec spec/services/ai_concierge_v3`
- 200 examples, 0 failures
- `bundle exec rspec spec/requests/api/v1/ai_concierge/inquiries_spec.rb`
- 35 examples, 0 failures
- `bundle exec rubocop --cache false app/services/ai_concierge_v3 spec/services/ai_concierge_v3 spec/requests/api/v1/ai_concierge/inquiries_spec.rb`
- no offenses
