# Slot Management and Merging

## `SlotMerger` Behavior

- merge new slots into active branch
- preserve valid upstream slots across corrections
- normalize `days`, `nights`, and derived `check_out`
- clear stale downstream state when timing or party composition changes

## Required State Invalidation

When booking timing changes, clear:
- `suggested_options`
- `pending_selection`
- `confirmation_candidate`
- `selected_option`

When party composition changes, clear:
- `suggested_options`
- `pending_selection`
- `confirmation_candidate`
- `selected_option`

## `BookingInputNormalizer` Behavior

- strip hallucinated timing, duration, checkout, and month segment slots unless explicit in the message
- preserve correction turns
- extract pure numeric guest-count answers when the pending question is guest count
- guard `party_size_total`, `adults`, and `children` against LLM over-inference
- resolve explicit `late this month` / `early this month` / `mid this month` against the current month
- clear stale `month_segment` for bare `this month` so the flow asks for exact date or assumption range

## `pending_selection` Shape

```json
{
  "check_in": "2026-05-21",
  "room_type_name": "Ocean Villa King",
  "candidate_room_type_names": ["Ocean Villa King", "Executive Penthouse"]
}
```

## Rate Plan Selection

When an option has multiple rate plans, `selected_rate_plan_id` and `selected_rate_plan_name` are stored in the branch after the guest picks one:

- `selected_rate_plan_id` — the database ID of the chosen `RatePlan`
- `selected_rate_plan_name` — the display name (e.g. "Standard Rate", "Non-Refundable Rate")

These fields are set during `handle_rate_plan_selection` in `BookingOrchestrator` and cleared on timing/party changes via `clear_downstream!`.

## Branch Fields Reference

| Field | Description |
|-------|-------------|
| `target_month` | Numeric month (1-12) |
| `target_year` | Numeric year |
| `month_segment` | "early", "mid", "late", or null |
| `check_in` | ISO date string |
| `check_out` | ISO date string |
| `nights` | Number of nights |
| `days` | Number of days |
| `room_count` | Number of rooms (default 1) |
| `party_size_total` | Total guests |
| `adults` | Number of adults |
| `children` | Number of children |
| `suggested_options` | Array of option groups from `search_booking_options` |
| `suggestion_set_version` | Incremented on each new search |
| `pending_selection` | Disambiguation context for option/date follow-ups |
| `confirmation_candidate` | The option ready for confirmation |
| `selected_option` | The option that was selected |
| `selected_rate_plan_id` | ID of the chosen rate plan |
| `selected_rate_plan_name` | Name of the chosen rate plan |

## Search Window Rules

- `early august` -> days `1..10`
- `mid august` -> days `11..20`
- `late august` -> days `21..end_of_month`
- `august` -> whole month
- `this month` -> current calendar month, with no segment unless the guest said early/mid/late
- `next month` -> next calendar month
