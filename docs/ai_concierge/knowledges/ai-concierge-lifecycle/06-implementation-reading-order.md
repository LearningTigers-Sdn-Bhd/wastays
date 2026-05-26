# Implementation Reading Order

## Source Navigation

1. `app/services/ai_concierge_v3/orchestration/inquiry_responder.rb` — public entry point
2. `app/services/ai_concierge_v3/orchestration/turn_orchestrator.rb` — main request lifecycle
3. `app/services/ai_concierge_v3/orchestration/transition_policy.rb` — flow control
4. `app/services/ai_concierge_v3/state/slot_merger.rb` — slot merging
5. `app/services/ai_concierge_v3/state/conversation_task_manager.rb` — task state
6. `app/services/ai_concierge_v3/matching/room_type_matcher.rb` — room resolution
7. `app/services/ai_concierge_v3/message_builders/` — reply rendering
8. `app/services/ai_concierge_v3/tools/` — tool implementations

## Key Boundaries

- the interpreter is responsible for structured interpretation only
- the messenger is responsible for deterministic reply routing only
- message builders are responsible for final reply text
- state changes, transition decisions, and tool execution stay in Ruby
- prospect identity is persisted through `Prospect` and `ProspectConversationState`
- anonymous/incognito state is outside the current V3 contract
