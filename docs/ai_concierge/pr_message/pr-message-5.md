# Add room rate routing, booking date range resolver, and n8n wait-time end control

## Brief Background

Three improvements to the AI Concierge booking flow: room rate/price questions were leaking into hotel knowledge routing instead of starting a booking flow, date range replies like `16-18 June` were not being parsed deterministically, and n8n timeouts had no safe kill-switch — letting stale messages reach the LLM during active booking flows.

## Solution

### Room Rate Intent Routing (V5.2)

- Force-routed room rate/price/cost questions (`what is room rate?`, `what is room price?`, `how much is the room?`) to the booking flow when no active booking branch exists.
- Added a room-rate-specific timing prompt: *"Dear guest, room rates depend on the booking dates and room types. Which date or month do you plan to arrive for check-in?"*
- Preserved hotel-information routing for service-price questions like `how much is room service?`.

### Booking Date Range Resolver (V5.3)

- Rephrased the standard booking timing prompt to *"Sure, which date or month do you plan to arrive for check-in?"*
- Added deterministic date-range parsing covering same-month (`16-18 June`), cross-month (`31 May - 2 June`), and cross-year (`31 Dec - 2 Jan`) formats.
- Derived `check_in`, `check_out`, `nights`, and `days` from explicit ranges.
- Added month clarification for monthless ranges (`16-18` -> *"You said 16-18, but which month?"*).
- Resolved month follow-ups (`this month`, `next month`, `{n} months from now`, month names) for pending ranges, with month names resolving to the next occurrence around year boundaries.
- Hardened parsing so unrelated two-number slot answers (e.g., party-split replies) do not hijack booking state.

### n8n Wait-Time End Control (V5.4)

- Added deterministic `codename: wait-time-end` sentinel detection in `ConversationControlPolicy`.
- Check runs before max-turn handling and before LLM interpretation, making it immune to interpretation errors.
- Force-ends the conversation without asking for end confirmation, even during active booking flows.
- Resets incomplete `booking_task` to idle, clears `active_flow`/`active_topic`/`pending_question`, persists `flow_status: "ended"` with `end_reason: "wait_time_end"`.
- Context-aware replies: generic timeout vs. booking-in-progress copy.

## Files Changed

```
app/services/ai_concierge/
├── message_builders/
│   └── booking_actions_builder.rb                       (modified)
└── orchestration/
    ├── booking/
    │   ├── action_resolver.rb                            (modified)
    │   ├── input_normalizer.rb                           (modified)
    │   └── orchestrator.rb                               (modified)
    ├── conversation/
    │   └── control_handler.rb                            (modified)
    ├── core/
    │   ├── conversation_control_policy.rb                (modified)
    │   └── information_intent_guard.rb                   (modified)
    └── turn_orchestrator.rb                              (modified)

docs/ai_concierge/
├── changelog.md                                          (modified)
├── knowledges/
│   ├── ai-concierge-lifecycle/
│   │   └── 02-state-transitions-and-orchestration.md     (modified)
│   ├── booking-lifecycle/
│   │   ├── 01-booking-flow-state-machine.md              (modified)
│   │   └── 02-slot-management-and-merging.md             (modified)
│   └── hotel-knowledge/
│       └── 01-hotel-info-tools.md                        (modified)
├── pr_message/
│   └── pr-message-5.md                                   (new)
└── test-cases/
    ├── booking-lifecycle/
    │   └── 01-good-happy-path-booking.md                 (modified)
    └── hotel-knowledge/
        └── 03-edge-amenity-routing-ambiguity.md          (modified)

spec/services/ai_concierge/
├── message_builders/
│   └── booking_actions_builder_spec.rb                   (modified)
└── orchestration/
    ├── booking/
    │   ├── action_resolver_spec.rb                       (modified)
    │   └── input_normalizer_spec.rb                      (modified)
    ├── conversation/
    │   └── control_handler_spec.rb                       (modified)
    ├── core/
    │   ├── conversation_control_policy_spec.rb           (modified)
    │   └── information_intent_guard_spec.rb              (modified)
    └── turn_orchestrator_spec.rb                         (modified)
```

## Verification

- `bundle exec rspec spec/services/ai_concierge`
- 168 examples, 0 failures across the 3 feature areas
- `bundle exec rubocop --cache false app/services/ai_concierge spec/services/ai_concierge`
- no offenses

## Risk Notes

- The `codename: wait-time-end` sentinel must stay in sync with the n8n workflow payload — if n8n changes the timeout message format, `wait_time_end?` must be updated.
- Date-range parsing is scoped to timing collection contexts only, but edge-case date-like phrases in guest-count or party-split replies are guarded by `date_range_clarification_allowed?`.
- Room rate routing to booking flow means guests asking about rates will enter the full booking flow — this is intentional so rates can be quoted with date and room-type context.
