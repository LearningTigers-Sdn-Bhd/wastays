# Current onboarding behavior

Checked against the local checkout on 2026-10-09. This document covers lifecycle,
readiness, and notification timing. It does not establish production rollout state.

## Lifecycle

```text
setup -> pending_review -> ready_to_launch -> live -> suspended
```

The current status list is defined in [Hotel](../../app/models/hotel.rb).
Admin approval and owner launch are separate actions.

| Action | Result | Implementation |
|---|---|---|
| Submit setup | The hotel enters `pending_review`; administrators receive a notification. | [SubmitOnboarding](../../app/services/onboarding/submit_onboarding.rb) |
| Approve setup | The hotel enters `ready_to_launch`; owners receive a request to choose how to launch. | [ApproveOnboarding](../../app/services/onboarding/approve_onboarding.rb) |
| Complete the keep/reset decision | The hotel enters `live`; launch notifications and draft invitations are queued. | [CompleteTraining](../../app/services/onboarding/complete_training.rb) |

Approval checks the submitted configuration and current readiness. It extends rates
and availability before checking the current 365-day window.

The owner chooses whether to keep training activity or reset it. A requested reset
must finish before launch. Launch checks the approved configuration and current
readiness again. Training appointment records do not replace this decision.

## Readiness and submission history

[Readiness](../../app/services/onboarding/readiness.rb) requires one year of sellable
rates and availability, together with the other required section decisions.

[ApproveOnboarding](../../app/services/onboarding/approve_onboarding.rb) and
[CompleteTraining](../../app/services/onboarding/complete_training.rb) check coverage
from the current date through 364 days later.
[ExtendAvailability](../../app/services/onboarding/extend_availability.rb) handles
the coverage extension. These checks are separate from the submitted snapshot.

## Notification timing

[CreateDeliveries](../../app/services/onboarding/create_deliveries.rb) defines the
durable delivery records.

| Event | Queued deliveries |
|---|---|
| Submission | `admin_submitted` for the administrators selected by `DeliveryRecipients.admins_for` |
| Admin approval | `owner_launch_decision_required` |
| Launch | `owner_approved`, draft staff and corporate invitations, and `agent_approved` when a linked agent recipient exists |

The method named `CreateDeliveries.for_approval` queues staff and corporate
invitations. Its current caller is `CompleteTraining`, after the transition to `live`.
The method name does not mean that invitations are sent during admin review.

## Historical records

[IMPLEMENTATION_MAP.md](IMPLEMENTATION_MAP.md) records the Phase 0 baseline.
[PLAN.md](PLAN.md) and the [phase handoffs](handoffs/README.md) retain the delivery
decisions and validation results from their recorded dates.

Use those documents to understand earlier decisions. Read the current services
before treating an old task, file path, or rollout note as current work.
