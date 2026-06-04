# Architecture Overview

## Hybrid Workflow

AiConcierge uses a hybrid architecture where:

- **LLM handles structured interpretation only** — converting raw user messages into structured intents, slots, and signals
- **Ruby handles everything else** — state management, transitions, validation, tool execution, side effects, and guest-facing reply rendering

## Core Principle

> The interpreter is never trusted for final state changes without Ruby guards.

## AI Responsibilities

- interpret the user's message into structured meaning
- classify an internal `message_type` before intent/topic mapping
- return `message_type`, slots, intent, tool hints, and conversation signals only

## Ruby Responsibilities

- load and persist conversation state
- manage booking branches
- validate legal transitions
- decide which tools may run
- execute tools
- invalidate stale suggestion sets
- guard against invented timing, duration, and guest-count splits
- preserve disambiguation context across turns
- keep compact state summaries instead of sending full chat history to the interpreter
- render deterministic guest-facing replies
- generate booking links through the existing quote flow

## Target Workflow

1. user sends message
2. `Conversation::SessionLoader` resolves/locks the prospect and records the inbound turn
3. `Conversation::InterpretationPipeline` builds compact state context and calls `InterpreterAgent`
4. `Conversation::ControlHandler` handles cancellation/end/max-turn decisions
5. `Conversation::InterpretationPipeline` applies deterministic guards, merges safe slots, and decides the next action
6. `TurnOrchestrator` delegates to booking, hotel-knowledge, booking-context, or fallback handlers
7. `Conversation::ResponsePersister` renders the reply, persists state, records outbound message, and returns public payload

## Ownership Boundaries

- `TurnOrchestrator`: public entrypoint and high-level delegation spine.
- `Conversation::SessionLoader`: prospect resolution/creation, per-prospect turn locking, state loading/reactivation, inbound message recording, and max-turn checks.
- `Conversation::InterpretationPipeline`: summary building, interpreter call, schema validation, deterministic guards, booking context prep, slot merge, and transition decision.
- `Conversation::ControlHandler`: booking-attempt cancellation, end confirmation, explicit end, declined end, and max-turn responses.
- `Conversation::ResponsePersister`: messenger invocation, state patch persistence, outbound message recording, direct payload completion, and final public payload.
- `Conversation::BookingContextHandler`: existing-booking context tool execution and domain result shaping.
- `Core::TransitionPolicy`: high-level action routing only; it does not decide booking sub-steps.
- `Core::ConversationControlPolicy`: deterministic cancel/end conversation-control decisions.
- `Core::InformationIntentGuard`: deterministic hotel/property amenities and facilities correction before routing.
- `Core::InquiryResponder`, `Core::Result`, and `Core::ResponsePayloadBuilder`: public entry validation, service result envelope, and public payload shape.
- `Booking::Orchestrator`: booking prompts and high-level booking sub-flow coordination.
- `Booking::ActionResolver`: next booking sub-step resolution.
- `Booking::SelectionHandler`: option/date/room ambiguity and pending-selection handling.
- `Booking::RatePlanSelectionHandler`: deterministic rate-plan selection follow-ups.
- `Booking::CompletionHandler`: booking URL generation, completion/archive semantics, and safe URL-failure fallback.
- `Booking::ResumeHandler`: suspended booking resume behavior.
- `Booking::RevisionPolicy`: booking-ready rate/room revision detection.
- `HotelKnowledge::Orchestrator`: hotel policy, general hotel info, FAQ, nearby attractions, and room information coordination.
- `HotelKnowledge::ToolRouter`: hotel-knowledge intent/topic to tool/reply mapping.
- `HotelKnowledge::StateHandler`: `information_task` updates and booking suspension on interruptions.
- `HotelKnowledge::DiagnosticRecorder`: hotel-knowledge diagnostic recording context.
- `HotelKnowledge::RoomReplyResolver`: room information result to reply-type mapping.
- `ConversationTaskManager`: V2 task-state normalization, legacy read migration, activate/suspend/resume/archive, and avoiding legacy writes.
- `Booking::InputNormalizer`: deterministic booking slot guards before merge.

## Public Payload Stability

V4 adds internal interpreter/state fields, but the public inquiry response stays unchanged:

- `reply_message`
- `needs_human_support`
- `action_name`
- `prospect_public_id`
