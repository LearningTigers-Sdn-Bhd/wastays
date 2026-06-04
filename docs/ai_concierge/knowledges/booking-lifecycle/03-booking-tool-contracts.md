# Booking Tool Contracts

## `search_booking_options`

- Path: `app/services/ai_concierge_v3/tools/booking/search_booking_options_tool.rb`
- Purpose: search available booking options for the current branch inputs
- Inputs: hotel, target_month, target_year, month_segment, optional check_in, optional check_out, adults, children, room_count, nights
- Output: grouped options with room type identity, dates, prices, positions, and selection IDs

```json
[
  {
    "room_type_id": 123,
    "room_type_name": "Ocean Villa King",
    "options": [
      {
        "selection_id": "room_type_123_option_1",
        "position": 1,
        "check_in": "2026-07-01",
        "check_out": "2026-07-03",
        "nights": 2,
        "total_price": 520.0,
        "currency": "MYR",
        "adults": 2,
        "children": 0,
        "room_count": 1,
        "rate_plans": [
          { "rate_plan_id": 1, "name": "Standard Rate", "total_price": 520.0, "currency": "MYR" },
          { "rate_plan_id": 2, "name": "Non-Refundable Rate", "total_price": 468.0, "currency": "MYR" }
        ]
      }
    ]
  }
]
```

- Uses a scoring-based date alignment algorithm to ensure consistent check-in/out windows across all room types.

## `select_booking_option`

- Path: `app/services/ai_concierge_v3/tools/booking/select_booking_option_tool.rb`
- Purpose: resolve selection input against the current shown suggestion set
- Inputs: optional option_number, suggested_options, suggestion_set_version, optional selection_id, optional check_in, raw message, optional pending_selection
- Success output: selected option payload and suggestion set version
- Failure output: `invalid_selection`, `ambiguous_option_selection`, `ambiguous_date_selection`, `room_type_requires_option_number`

Supported selection styles:
- `Ocean Villa King option 1`
- `Executive Penthouse on May 21`
- `option 1` when only one room-type group is relevant
- `i chose option 1`
- partial room type matches like `garden prestige` and `executive`
- reordered shorthand like `king ocean`
- common aliases like `exec`
- minor typos when the match remains unique

## `generate_booking_url`

- Path: `app/services/ai_concierge_v3/tools/booking/generate_booking_url_tool.rb`
- Purpose: convert a confirmed option into a booking quote link
- Inputs: selected option, resolved prospect phone, optional `rate_plan_id`
- Success output: booking_url, total_amount, currency, expires_at, quote_token
- Failure output: `success=false`, safe `error`, and internal `error_code`
- Lifecycle side effect: successful booking URL generation ends the current conversation with `end_reason: "booking_url_generated"`
- Failure behavior: validates selected option shape before quote creation, returns safe fallback, and does not archive booking as completed
- Rate plan: when `rate_plan_id` is provided, the quote uses that plan's pricing; otherwise falls back to the lowest available rate

Internal booking URL failure codes:
- `invalid_selection`
- `missing_room_type_id`
- `missing_check_in`
- `missing_check_out`
- `invalid_dates`
- `quote_creation_failed`
- `quote_missing`

## Rate Plan Selection

Rate plan selection is resolved deterministically inside `BookingOrchestrator`.

Supported rate-plan selection styles:
- exact or partial rate-plan names when unique
- ordinal replies such as `first`, `second`, `1`, or `2`
- price intent such as `cheapest` or `lowest`
- `standard` when exactly one standard-like plan exists
- `refundable` and `non-refundable`, with explicit protection against matching `refundable` to `Non-Refundable Rate`

Ambiguous rate-plan matches re-ask the rate-plan question and leave the selected option unconfirmed.
