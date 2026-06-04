# Implementation Reading Order

## Source Navigation

1. `app/services/ai_concierge_v3/orchestration/core/inquiry_responder.rb` — public entry point
2. `app/services/ai_concierge_v3/orchestration/turn_orchestrator.rb` — main request lifecycle
3. `app/services/ai_concierge_v3/orchestration/conversation/session_loader.rb` — prospect/session loading and turn lock
4. `app/services/ai_concierge_v3/orchestration/conversation/interpretation_pipeline.rb` — interpretation, guards, merge, and route decision
5. `app/services/ai_concierge_v3/orchestration/conversation/control_handler.rb` — cancel/end/max-turn responses
6. `app/services/ai_concierge_v3/orchestration/conversation/response_persister.rb` — messenger, persistence, outbound records, public payload
7. `app/services/ai_concierge_v3/orchestration/conversation/booking_context_handler.rb` — existing-booking context domain result
8. `app/services/ai_concierge_v3/state/conversation_summary_builder.rb` — compact interpreter context
9. `app/services/ai_concierge_v3/agents/interpreter_agent.rb` — message-type-first structured interpretation
10. `app/services/ai_concierge_v3/orchestration/core/information_intent_guard.rb` — deterministic hotel-knowledge routing guard
11. `app/services/ai_concierge_v3/orchestration/booking/input_normalizer.rb` — deterministic booking slot guard
12. `app/services/ai_concierge_v3/orchestration/core/transition_policy.rb` — flow control
13. `app/services/ai_concierge_v3/orchestration/core/conversation_control_policy.rb` — end/cancel conversation-control decisions
14. `app/services/ai_concierge_v3/orchestration/booking/orchestrator.rb` — booking sub-flow coordinator
15. `app/services/ai_concierge_v3/orchestration/booking/action_resolver.rb` — next booking sub-step resolution
16. `app/services/ai_concierge_v3/orchestration/booking/selection_handler.rb` — option/date/room selection ambiguity handling
17. `app/services/ai_concierge_v3/orchestration/booking/rate_plan_selection_handler.rb` — rate-plan follow-up handling
18. `app/services/ai_concierge_v3/orchestration/booking/completion_handler.rb` — booking URL generation and completion/archive behavior
19. `app/services/ai_concierge_v3/orchestration/booking/resume_handler.rb` — suspended booking resume behavior
20. `app/services/ai_concierge_v3/orchestration/booking/revision_policy.rb` — booking-ready rate/room revision detection
21. `app/services/ai_concierge_v3/orchestration/hotel_knowledge/orchestrator.rb` — hotel-knowledge sub-flow coordinator
22. `app/services/ai_concierge_v3/orchestration/hotel_knowledge/tool_router.rb` — hotel-knowledge tool/reply routing
23. `app/services/ai_concierge_v3/orchestration/hotel_knowledge/state_handler.rb` — information task and booking suspension state
24. `app/services/ai_concierge_v3/orchestration/hotel_knowledge/diagnostic_recorder.rb` — diagnostic recording context
25. `app/services/ai_concierge_v3/orchestration/hotel_knowledge/room_reply_resolver.rb` — room result reply mapping
26. `app/services/ai_concierge_v3/state/slot_merger.rb` — slot merging
27. `app/services/ai_concierge_v3/state/conversation_task_manager.rb` — task state
28. `app/services/ai_concierge_v3/matching/room_type_matcher.rb` — room resolution
29. `app/services/ai_concierge_v3/matching/rate_plan_matcher.rb` — rate-plan resolution
30. `app/services/ai_concierge_v3/message_builders/` — reply rendering
31. `app/services/ai_concierge_v3/tools/` — tool implementations

## Key Boundaries

- the interpreter is responsible for structured interpretation only
- `message_type` is internal guidance and does not change the public response contract
- the interpreter receives compact state summaries, not full conversation transcripts by default
- the messenger is responsible for deterministic reply routing only
- message builders are responsible for final reply text
- state changes, transition decisions, and tool execution stay in Ruby
- conversation lifecycle, conversation control, booking handlers, hotel-knowledge handlers, and matcher rules live in focused Ruby objects
- prospect identity is persisted through `Prospect` and `ProspectConversationState`
- anonymous/incognito state is outside the current V3 contract
