# Implementation Reading Order

## Source Navigation

1. `app/services/ai_concierge_v3/orchestration/inquiry_responder.rb` — public entry point
2. `app/services/ai_concierge_v3/orchestration/turn_orchestrator.rb` — main request lifecycle
3. `app/services/ai_concierge_v3/state/conversation_summary_builder.rb` — compact interpreter context
4. `app/services/ai_concierge_v3/agents/interpreter_agent.rb` — message-type-first structured interpretation
5. `app/services/ai_concierge_v3/orchestration/information_intent_guard.rb` — deterministic hotel-knowledge routing guard
6. `app/services/ai_concierge_v3/orchestration/booking/input_normalizer.rb` — deterministic booking slot guard
7. `app/services/ai_concierge_v3/orchestration/transition_policy.rb` — flow control
8. `app/services/ai_concierge_v3/orchestration/conversation_control_policy.rb` — end/cancel conversation-control decisions
9. `app/services/ai_concierge_v3/orchestration/booking/orchestrator.rb` — booking sub-flow coordinator
10. `app/services/ai_concierge_v3/orchestration/booking/action_resolver.rb` — next booking sub-step resolution
11. `app/services/ai_concierge_v3/orchestration/booking/selection_handler.rb` — option/date/room selection ambiguity handling
12. `app/services/ai_concierge_v3/orchestration/booking/rate_plan_selection_handler.rb` — rate-plan follow-up handling
13. `app/services/ai_concierge_v3/orchestration/booking/completion_handler.rb` — booking URL generation and completion/archive behavior
14. `app/services/ai_concierge_v3/orchestration/booking/resume_handler.rb` — suspended booking resume behavior
15. `app/services/ai_concierge_v3/orchestration/booking/revision_policy.rb` — booking-ready rate/room revision detection
16. `app/services/ai_concierge_v3/state/slot_merger.rb` — slot merging
17. `app/services/ai_concierge_v3/state/conversation_task_manager.rb` — task state
18. `app/services/ai_concierge_v3/matching/room_type_matcher.rb` — room resolution
19. `app/services/ai_concierge_v3/matching/rate_plan_matcher.rb` — rate-plan resolution
20. `app/services/ai_concierge_v3/message_builders/` — reply rendering
21. `app/services/ai_concierge_v3/tools/` — tool implementations

## Key Boundaries

- the interpreter is responsible for structured interpretation only
- `message_type` is internal guidance and does not change the public response contract
- the interpreter receives compact state summaries, not full conversation transcripts by default
- the messenger is responsible for deterministic reply routing only
- message builders are responsible for final reply text
- state changes, transition decisions, and tool execution stay in Ruby
- conversation-control, booking revision, booking action resolution, booking handlers, and rate-plan matching live in focused Ruby objects
- prospect identity is persisted through `Prospect` and `ProspectConversationState`
- anonymous/incognito state is outside the current V3 contract
