# Enhance AI Concierge V3: hardening, refactoring, and cleanup

## Brief Background

The AI Concierge V3 feature needed production hardening — rate limiting to protect the API, optimistic locking to prevent race conditions on conversation state persistence, proper error types for prospect lookup failures, and cleanup of deprecated code paths and documentation that were no longer relevant.

## Solution

- **Rate limiting middleware**
  - Added `rack-attack` gem and `Rack::Attack` middleware
  - Added `config/initializers/rack_attack.rb` initializer
- **Optimistic locking**
  - Added `lock_version` column to `prospect_conversation_states` via migration
  - Enables stale-object detection on concurrent state writes
- **ProspectNotFoundError**
  - Introduced dedicated error class for prospect lookup failures
  - Added matching spec
- **Core service refactors**
  - `InterpreterAgent` — improved interpretation pipeline
  - `TurnOrchestrator` — removed deprecated `identity_mode` parameter, streamlined turn logic
  - `SlotMerger` — enhanced state merging for booking slots
  - `SearchBookingOptionsTool` — refined date alignment and option grouping
- **Deprecation cleanup**
  - Removed `BranchManager` service and its spec (replaced by `ConversationTaskManager`)
  - Removed old V3 design docs (`file-structure.md`, `research.md`, `spec.md`, `test.md`, `tooling.md`)
- **Spec improvements**
  - Added auth/validation specs (401 unauthorized, 403 forbidden, blank message, max length)
  - Removed deprecated `identity_mode:` keyword from orchestrator specs
- **Rake tasks**
  - Added `hotel_ops:clear_ai_concierge` task for clearing concierge data per hotel
  - Extended `hotel_ops:clean_state` to clear concierge data and recalibrate nearby attractions

## File Changes

```
app/services/ai_concierge/
├── prospect_not_found_error.rb                          (new)
├── agents/
│   ├── interpreter_agent.rb                             (modified)
│   └── messenger_agent.rb
├── matching/
│   └── room_type_matcher.rb
├── message_builders/
│   ├── base_builder.rb
│   ├── booking_actions_builder.rb
│   ├── fallback_builder.rb
│   ├── hotel_info_builder.rb
│   └── room_info_builder.rb
├── orchestration/
│   ├── booking_input_normalizer.rb
│   ├── booking_orchestrator.rb
│   ├── information_intent_guard.rb
│   ├── inquiry_responder.rb                             (modified)
│   ├── librarian_orchestrator.rb
│   ├── response_payload_builder.rb
│   ├── result.rb
│   ├── transition_policy.rb
│   └── turn_orchestrator.rb                             (modified)
├── schemas/
│   └── interpretation_schema.rb
├── state/
│   ├── conversation_summary_builder.rb
│   ├── conversation_task_manager.rb
│   ├── slot_merger.rb                                   (modified)
│   └── state_patch_builder.rb
└── tools/
    ├── tool_registry.rb
    ├── booking/
    │   ├── generate_booking_url_tool.rb
    │   ├── search_booking_options_tool.rb                (modified)
    │   └── select_booking_option_tool.rb
    ├── hotel_information/
    │   ├── get_booking_context_tool.rb
    │   ├── get_general_hotel_info_tool.rb
    │   ├── get_hotel_faq_tool.rb
    │   ├── get_hotel_policy_tool.rb
    │   └── get_nearby_attractions_tool.rb
    └── room_information/
        └── get_room_type_details_tool.rb

spec/services/ai_concierge/
├── prospect_not_found_error_spec.rb                     (new)
├── agents/
│   ├── interpreter_agent_spec.rb
│   └── messenger_agent_spec.rb
├── matching/
│   └── room_type_matcher_spec.rb
├── message_builders/
│   ├── base_builder_spec.rb
│   ├── booking_actions_builder_spec.rb
│   ├── fallback_builder_spec.rb
│   ├── hotel_info_builder_spec.rb
│   └── room_info_builder_spec.rb
├── orchestration/
│   ├── booking_input_normalizer_spec.rb
│   ├── booking_orchestrator_spec.rb
│   ├── information_intent_guard_spec.rb
│   ├── inquiry_responder_spec.rb
│   ├── librarian_orchestrator_spec.rb
│   ├── response_payload_builder_spec.rb
│   ├── result_spec.rb
│   ├── transition_policy_spec.rb
│   └── turn_orchestrator_spec.rb                        (modified)
├── schemas/
│   └── interpretation_schema_spec.rb
├── state/
│   ├── conversation_summary_builder_spec.rb
│   ├── conversation_task_manager_spec.rb
│   ├── slot_merger_spec.rb
│   └── state_patch_builder_spec.rb
└── tools/
    ├── tool_registry_spec.rb
    ├── booking/
    │   ├── generate_booking_url_tool_spec.rb
    │   ├── search_booking_options_tool_spec.rb
    │   └── select_booking_option_tool_spec.rb
    ├── hotel_information/
    │   ├── get_booking_context_tool_spec.rb
    │   ├── get_general_hotel_info_tool_spec.rb
    │   ├── get_hotel_faq_tool_spec.rb
    │   ├── get_hotel_policy_tool_spec.rb
    │   └── get_nearby_attractions_tool_spec.rb
    └── room_information/
        └── get_room_type_details_tool_spec.rb

spec/requests/api/v1/ai_concierge/
└── inquiries_spec.rb                                     (modified)

config/
├── application.rb                                        (modified)
└── initializers/
    └── rack_attack.rb                                    (new)

Gemfile                                                    (modified)
Gemfile.lock                                               (modified)

db/
├── migrate/
│   └── 20260525110203_add_lock_version_to_prospect_conversation_states.rb (new)
└── schema.rb                                              (modified)

lib/tasks/
└── hotel_ops.rake                                         (modified)

Removed:
├── app/services/ai_concierge/state/branch_manager.rb
├── spec/services/ai_concierge/state/branch_manager_spec.rb
├── docs/ai-concierge/v3/
│   ├── file-structure.md
│   ├── research.md
│   ├── spec.md
│   ├── test.md
│   └── tooling.md
```

## Test Spec

- **1941 examples, 0 failures** — all 8 CI stages pass (RuboCop, Brakeman, Bundle Audit, Importmap Audit, Tailwind Build, DB Setup, Parallel RSpec)
- New specs:
  - `spec/requests/api/v1/ai_concierge/inquiries_spec.rb` — 4 new auth/validation scenarios
  - `spec/services/ai_concierge/prospect_not_found_error_spec.rb` — error class unit test
- Updated specs:
  - `spec/services/ai_concierge/orchestration/turn_orchestrator_spec.rb` — removed `identity_mode:` param across all examples
- Removed specs:
  - `spec/services/ai_concierge/state/branch_manager_spec.rb` — deprecated alongside `BranchManager`
