# V4: Interpreter Message-Type and Compact State Context

## Problem

The interpreter could confuse booking flow messages with hotel knowledge questions, especially while stale booking state existed. Short follow-ups such as `yes`, `option 2`, `the cheaper one`, and `what about deluxe?` also needed state context, but sending full conversation history would add noise and cost.

Screenshots exposed three concrete failures:

- hotel information/policy questions could resume a stale booking search
- `this month` could reuse a stale `early/mid/late` segment
- cancelling a booking attempt could immediately restart booking instead of asking what the guest wants next

## Completed Work

- [x] Added internal `message_type` to interpreter output and schema validation
- [x] Reworked interpreter prompt order:
  1. classify `message_type`
  2. map to existing `intent` and `topic`
  3. extract relevant slots only
  4. set conversation signals
- [x] Kept the public API response unchanged
- [x] Enhanced compact interpreter state with latest assistant question, shown options, rate plans, and selected option summary
- [x] Kept full conversation history out of the interpreter input by default
- [x] Added guards for booking-advice and hotel-service questions
- [x] Prevented hotel policy/info interruptions from resuming stale suspended booking searches
- [x] Handled `late this month` against the current month
- [x] Made bare `this month` ask for exact date or assumption range instead of reusing stale timing
- [x] Reset stale booking branches when a generic fresh booking request follows no-options state
- [x] Changed cancel-attempt flow to clear booking state and ask the next step
- [x] Accepted nested inquiry payload params without unpermitted route-param noise

## Message-Type Contract

Supported internal types:

- `booking_request`
- `booking_selection`
- `booking_confirmation`
- `hotel_info_question`
- `hotel_policy_question`
- `room_info_question`
- `existing_booking_question`
- `conversation_control`
- `greeting_or_unknown`

`message_type` is not persisted or returned publicly. It helps interpretation only; Ruby services still decide legal behavior.

## Key Behavior

- `tell me about executive suite` -> room info
- `I want executive suite on June 23` -> booking request
- `option 1 executive` -> booking selection when options were shown
- `do you have parking?` -> hotel information
- `booking policy?` -> hotel policy
- `what should I be aware of during booking in this hotel?` -> hotel policy/advice
- `yes` with `pending_question=confirm_selection` -> booking confirmation
- `yes` with `pending_question=guest_count` -> not booking confirmation
- `cancel my attempt for booking` -> reset booking task, keep conversation active, ask next step

## Verification

- `bundle exec rspec spec/services/ai_concierge_v3`
- 185 examples, 0 failures
- `bundle exec rspec spec/requests/api/v1/ai_concierge/inquiries_spec.rb`
- 34 examples, 0 failures
