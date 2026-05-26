# Architecture Overview

## Hybrid Workflow

AiConciergeV3 uses a hybrid architecture where:

- **LLM handles structured interpretation only** — converting raw user messages into structured intents, slots, and signals
- **Ruby handles everything else** — state management, transitions, validation, tool execution, side effects, and guest-facing reply rendering

## Core Principle

> The interpreter is never trusted for final state changes without Ruby guards.

## AI Responsibilities

- interpret the user's message into structured meaning
- return slots, intent, and conversation signals only

## Ruby Responsibilities

- load and persist conversation state
- manage booking branches
- validate legal transitions
- decide which tools may run
- execute tools
- invalidate stale suggestion sets
- guard against invented timing, duration, and guest-count splits
- preserve disambiguation context across turns
- render deterministic guest-facing replies
- generate booking links through the existing quote flow

## Target Workflow

1. user sends message
2. `InterpreterAgent` returns structured interpretation
3. `TurnOrchestrator` applies deterministic guards to timing, duration, and guest count
4. orchestrator merges safe slots into state and decides the next action
5. orchestrator executes one or more deterministic tools
6. orchestrator builds structured reply context
7. `MessengerAgent` renders `reply_message`
8. Ruby returns public payload and persists state updates

## Ownership Boundaries

- `TurnOrchestrator`: prospect resolution, state loading, interpreter call, deterministic guard invocation, high-level delegation, persistence, message rendering, and final payload.
- `TransitionPolicy`: high-level action routing only; it does not decide booking sub-steps.
- `BookingOrchestrator`: booking prompts, option search, option selection, confirmation, booking URL generation, booking completion/archive semantics, and safe URL-failure fallback.
- `LibrarianOrchestrator`: hotel policy, general hotel info, FAQ, nearby attractions, room information, `information_task`, and booking suspension on interruptions.
- `ConversationTaskManager`: V2 task-state normalization, legacy read migration, activate/suspend/resume/archive, and avoiding legacy writes.
- `BookingInputNormalizer`: deterministic booking slot guards before merge.
- `InformationIntentGuard`: deterministic hotel/property amenities and facilities correction before routing.
