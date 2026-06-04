# Architecture Overview

## Hybrid Workflow

AiConciergeV3 uses a hybrid architecture where:

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
2. `ConversationSummaryBuilder` builds compact state context
3. `InterpreterAgent` classifies internal `message_type`, then returns structured interpretation
4. `TurnOrchestrator` applies deterministic guards to timing, duration, and guest count
5. orchestrator merges safe slots into state and decides the next action
6. orchestrator executes one or more deterministic tools
7. orchestrator builds structured reply context
8. `MessengerAgent` renders `reply_message`
9. Ruby returns public payload and persists state updates

## Ownership Boundaries

- `TurnOrchestrator`: prospect resolution, per-prospect turn locking, state loading, interpreter call, deterministic guard invocation, high-level delegation, persistence, message rendering, and final payload.
- `TransitionPolicy`: high-level action routing only; it does not decide booking sub-steps.
- `Booking::Orchestrator`: booking prompts and high-level booking sub-flow coordination.
- `Booking::ActionResolver`: next booking sub-step resolution.
- `Booking::SelectionHandler`: option/date/room ambiguity and pending-selection handling.
- `Booking::RatePlanSelectionHandler`: deterministic rate-plan selection follow-ups.
- `Booking::CompletionHandler`: booking URL generation, completion/archive semantics, and safe URL-failure fallback.
- `Booking::ResumeHandler`: suspended booking resume behavior.
- `Booking::RevisionPolicy`: booking-ready rate/room revision detection.
- `LibrarianOrchestrator`: hotel policy, general hotel info, FAQ, nearby attractions, room information, `information_task`, and booking suspension on interruptions.
- `ConversationTaskManager`: V2 task-state normalization, legacy read migration, activate/suspend/resume/archive, and avoiding legacy writes.
- `Booking::InputNormalizer`: deterministic booking slot guards before merge.
- `InformationIntentGuard`: deterministic hotel/property amenities and facilities correction before routing.

## Public Payload Stability

V4 adds internal interpreter/state fields, but the public inquiry response stays unchanged:

- `reply_message`
- `needs_human_support`
- `action_name`
- `prospect_public_id`
