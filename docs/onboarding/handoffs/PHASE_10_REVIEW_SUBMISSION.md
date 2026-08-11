# Phase 10 — Review, submission, and invitations

Read `docs/onboarding/handoffs/README.md` first for the shared pattern and rules.

## Goal

An owner can review the full readiness report, submit onboarding safely, and have queued
invitations delivered exactly once.

`PLAN.md` §"Phase 10" is the scope authority.

## Prerequisite

All twelve preceding sections implemented. This phase is the one that turns the shell's
placeholder scaffolding into a real gate, so it genuinely cannot run early.

## Deliverables

- Group findings by phase
- Distinguish blocking issues, warnings, complete, skipped, and needs attention
- Link each finding to its owning page
- Re-run readiness **server-side** on submission
- Send queued staff invitations only after successful submission
- Send requested corporate invitations after successful submission
- Change the hotel to `pending_review` atomically with submission records
- Make submitted onboarding read-only
- Notify admins

## What already exists

`Onboarding::Readiness` (`app/services/onboarding/readiness.rb`) already returns
`Result(ready:, blocking_issues:, warnings:)` with `Finding(section_key:, severity:, message:)`.
Its current messages are generic ("Complete this required section."). This phase should
enrich findings with section-specific detail and phase grouping — the `Finding` struct
already carries `section_key`, so grouping by `SectionCatalog.fetch(key).phase` and linking
to `onboarding_section_path` is straightforward.

**Critically, `Readiness` treats `decision_metadata["placeholder"]` as blocking.** That is
the mechanism preventing submission while stub sections remain. When every phase is
implemented, no section should carry that flag — verify this explicitly, because a leftover
placeholder is a silent submission blocker.

`Onboarding::TransitionLifecycle` (`app/services/onboarding/transition_lifecycle.rb`)
already:

- enforces `setup -> pending_review` and re-runs `Readiness` server-side inside the guard
- writes the status change and a `submitted` audit event in one transaction
- rejects the transition when readiness fails

So the lifecycle half of submission is built. This phase adds the **side effects**:
invitations and admin notification, atomically with the transition.

## Idempotency is the hard requirement

"Delivery must be idempotent so retries do not send duplicate invitations or duplicate
submission effects."

`IMPLEMENTATION_MAP.md` §8 item 11 states the open problem directly: staff drafts are
stored in `onboarding_staff_drafts` without delivery, and **this phase must define an
idempotent draft-to-invitation delivery marker before sending them.** Phase 8 was asked to
settle the equivalent question for corporate invitation drafts — check what it chose and
stay consistent.

Design guidance: a per-draft `delivered_at` (or an invitation foreign key on the draft) is
simpler and more auditable than a per-submission flag, because it survives partial
delivery. Sending must be resumable, not all-or-nothing-from-scratch.

Note the transactional tension: the status transition must be atomic, but invitation
delivery involves outbound mail and should not sit inside that transaction. The usual
resolution is to commit the transition and submission records, then enqueue delivery jobs
that mark each draft delivered as they succeed. Confirm the approach with the user before
building it.

## Invitation services

| Need | Reuse | Note |
|---|---|---|
| Staff invitations | `StaffInvitations::CreateService`, `ResendService` | Sends immediately — call only after submission |
| Corporate invitations | `CorporateInvitations::CreateService`, `ResendService` | Same |
| Token model | `Invitation` (`app/models/invitation.rb`) | SHA-256 digest, 7-day expiry, rotation on resend |

`IMPLEMENTATION_MAP.md` §6 flags a semantic trap: existing staff acceptance always creates
a user with coarse role `hotel_staff`, while owner creation uses coarse role `admin` plus an
account-level Hotel Owner role. Do not blindly reuse the staff path for anything
owner-shaped.

## Read-only after submission

The shell already handles this: `OnboardingController#update` calls `redirect_read_only`
when `pending_review?`, and the presenter exposes `read_only?`. Verify every section
partial delivered in phases 5–9 actually honours `@presenter.read_only?` — this is the
first phase where that state is reachable in practice.

## Admin notification

Check what admin notification mechanism the app already uses before adding one. The admin
review queue reads hotels with `pending_review` status
(`app/models/hotel.rb:215-222`), so the queue populates itself; notification is the
additional signal.

## Open decisions — resolve before coding

1. **Do existing admin training sessions remain a launch prerequisite, a warning, or an
   independent process?** (`PLAN.md` open decision 3.) This determines whether
   `OnboardingSession` records appear in the readiness report at all. The implementation
   map recommends keeping them independent.
2. **Do live hotels retain a read-only onboarding summary indefinitely or only an audit
   record?** (`PLAN.md` open decision 5.) This affects what the review page renders
   post-launch.

## Tests

- Service specs: readiness grouping and finding links; submission happy path; submission
  refused when readiness fails; **retry sends nothing twice**
- Request specs: review page authorization, submit action, read-only enforcement after
  submission
- Job specs for invitation delivery, including partial-failure resume
- System spec: the full owner path ending in a successful submission

```bash
bin/test hotel_management
```

Phase 10 is an integration milestone — per `PLAN.md`, this is a reasonable point to run the
full suite rather than a single domain.

```bash
bin/ci
```

## Done when

An owner with every section resolved can submit; the hotel moves to `pending_review`
atomically with its submission record; queued staff and corporate invitations are
delivered exactly once even if submission is retried; onboarding becomes read-only; and
admins can see the hotel in their review queue.
