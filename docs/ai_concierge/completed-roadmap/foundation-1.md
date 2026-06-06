# Foundation 1: Core Booking Flow

## Completed
- Booking timing collection
- Duration collection
- Guest clarification (party split)
- Option suggestions with grouped room types and prices
- Option selection with ambiguity handling
- Confirmation before booking URL generation
- Booking URL generation through existing quote flow

## Completed — Second Slice
- Hotel-policy interruption and resume
- Booking context rendering
- Correction handling (timing/party changes)
- Another-booking branching

## Completed — Architecture Foundation
- Hybrid AI/Ruby workflow
- Deterministic reply rendering
- `ProspectConversationState` state container
- V2 task-state normalization
- `InformationIntentGuard` for amenity routing
- `BookingInputNormalizer` for hallucination guards
- Fuzzy room-type matching via `RoomTypeMatcher`
- Date alignment algorithm
- Tool registry pattern
- Message builder pattern
- Per-hotel AI provider configuration
- Rate limiting (60 req/min per API key, 20 req/min per IP)

## V3.1 — Rate Plan Selection
- Options now expose all rate plans (Standard Rate, Non-Refundable, etc.) with per-plan pricing
- Nested rendering: date option → rate plan sub-items
- New `rate_plan_selection` state when multiple rate plans exist
- Interpreter extracts `rate_plan_name` from guest messages
- Fuzzy rate plan name matching (accepts partial/natural language)
- `GenerateBookingUrlTool` passes `rate_plan_id` to `CreateQuote` for correct pricing
- Backward compatible: single-plan and legacy options skip the rate plan step
