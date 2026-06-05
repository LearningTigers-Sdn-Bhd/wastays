# V3.4: Black-Box Hotel Knowledge Routing

## Problem

Hotel knowledge is split into `policy`, `faq`, and `general_info`, but hotels may place content inconsistently. A guest can ask about parking, transportation, or house rules while the interpreter returns `booking_search`, causing the concierge to ask for booking dates instead of answering the information question.

## Completed Work

- [x] Broadened `InformationIntentGuard` to correct hotel knowledge questions before booking routing
- [x] Kept high-confidence policy phrases on `hotel_policy`, including policy, rules, house rules, cancellation, check-in, and check-out
- [x] Routed hotel service questions such as parking, transportation, shuttle, WiFi, breakfast, restaurant, spa, pool, amenities, and facilities to `hotel_information`
- [x] Preserved clear booking requests as booking flow, including room availability, book/reserve/quote, and date/month booking phrasing
- [x] Added cross-category fallback in `HybridAnswerBuilder`
- [x] Preserved active booking suspension/resume when a guarded hotel knowledge question interrupts booking

## Retrieval Behavior

Hybrid hotel knowledge tools first search the routed category. If no useful answer is found, retrieval retries across:

- `general_info`
- `faq`
- `policy`

Only after the cross-category retry fails should the tool use structured fallback text or an unavailable answer.

## Verification

- `bundle exec rspec spec/services/ai_concierge`
- 170 examples, 0 failures
- `bundle exec rubocop --cache false ...`
- no offenses
