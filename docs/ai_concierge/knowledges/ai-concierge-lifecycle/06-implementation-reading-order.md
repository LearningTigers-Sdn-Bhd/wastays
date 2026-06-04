# Implementation Reading Order

## Source Navigation

1. `app/services/ai_concierge_v3/orchestration/inquiry_responder.rb` — public entry point
2. `app/services/ai_concierge_v3/orchestration/turn_orchestrator.rb` — main request lifecycle
3. `app/services/ai_concierge_v3/state/conversation_summary_builder.rb` — compact interpreter context
4. `app/services/ai_concierge_v3/agents/interpreter_agent.rb` — message-type-first structured interpretation
5. `app/services/ai_concierge_v3/orchestration/information_intent_guard.rb` — deterministic hotel-knowledge routing guard
6. `app/services/ai_concierge_v3/orchestration/booking_input_normalizer.rb` — deterministic booking slot guard
7. `app/services/ai_concierge_v3/orchestration/transition_policy.rb` — flow control
8. `app/services/ai_concierge_v3/orchestration/conversation_control_policy.rb` — end/cancel conversation-control decisions
9. `app/services/ai_concierge_v3/orchestration/booking_revision_policy.rb` — booking-ready rate/room revision detection
10. `app/services/ai_concierge_v3/state/slot_merger.rb` — slot merging
11. `app/services/ai_concierge_v3/state/conversation_task_manager.rb` — task state
12. `app/services/ai_concierge_v3/matching/room_type_matcher.rb` — room resolution
13. `app/services/ai_concierge_v3/matching/rate_plan_matcher.rb` — rate-plan resolution
14. `app/services/ai_concierge_v3/message_builders/` — reply rendering
15. `app/services/ai_concierge_v3/tools/` — tool implementations

## Key Boundaries

- the interpreter is responsible for structured interpretation only
- `message_type` is internal guidance and does not change the public response contract
- the interpreter receives compact state summaries, not full conversation transcripts by default
- the messenger is responsible for deterministic reply routing only
- message builders are responsible for final reply text
- state changes, transition decisions, and tool execution stay in Ruby
- conversation-control, booking-revision, and rate-plan matching rules live in focused Ruby policy/matcher objects
- prospect identity is persisted through `Prospect` and `ProspectConversationState`
- anonymous/incognito state is outside the current V3 contract
