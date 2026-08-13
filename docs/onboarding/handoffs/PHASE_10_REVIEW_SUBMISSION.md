# Phase 10 — Review, submission, and invitations

Implemented on `feat/onboarding-shell` on 2026-08-13 together with Phase 11. This file
describes the delivered code, not the earlier proposal.

## Delivered outcome

An owner sees a grouped readiness ledger, submits through one idempotent endpoint, and
enters `pending_review`. Submission creates an immutable, versioned, secret-free snapshot
and durable delivery records in the same transaction. Invitations and lifecycle email are
processed after commit and remain retryable if external delivery fails.

## Main implementation

- `OnboardingSubmission` stores submitter/reviewer, status, idempotency key, submitted and
  reviewed timestamps, readiness snapshot, versioned configuration snapshot, digest, and
  review explanation. Submitted fields are read-only after creation.
- A partial unique database index permits only one `pending_review` submission per hotel.
- `OnboardingDelivery` is the application outbox for staff/corporate invitations and
  submission/change/approval email. Each effect has a unique idempotency key, status,
  attempts, error, and completion time.
- `Onboarding::DispatchPendingDeliveriesJob` retries pending/failed effects and recovers a
  delivery left `processing` by a stopped worker. `config/recurring.yml` sweeps every five
  minutes in production and demo.
- `Onboarding::SubmissionSnapshot` deliberately records OTA channel name and
  `credentials_supplied` only. It never reads or serializes the encrypted username or
  password. Delivery JSON never contains invitation tokens or credentials.
- `Onboarding::SubmitOnboarding` locks and reloads the hotel, reruns readiness, completes
  Review, creates the submission and outbox effects, transitions to `pending_review`, and
  writes the lifecycle audit event in one transaction. Effects enqueue after commit.
- Reusing the same idempotency key returns the successful submission. A different key
  while a pending submission exists returns that submission and creates nothing new.
- `HotelPortal::BaseController` rejects hotel mutations during `pending_review`; safe reads,
  profile/security, logout, and the idempotent submission response remain reachable.
- The old dashboard submission action and route were removed. The dashboard now sends the
  owner to `Review and submit` through `Continue property setup`.

## Readiness contract

Review does not block itself. Findings have stable error codes and staff-facing messages.
Readiness verifies current domain data as well as section state:

- complete property data and featured photo;
- the four standard roles and the permission fingerprint last confirmed by the owner;
- explicit staff and optional-section decisions;
- current tax confirmation and room-revenue tax fingerprint;
- at least one operationally valid room type;
- sell-mode pricing and one-year setup coverage;
- at least one active payment method.

`ConfirmRolePresets.permission_fingerprint` is the single calculation used at save and at
readiness time. Role order is the preset order (`hotel_owner`, `general_manager`,
`front_desk`, `housekeeper`), not alphabetical order. Changing the ordering changes the
digest and will falsely mark a saved section stale, so do not duplicate this calculation.

## Invitation semantics

- Drafts marked Send are processed after successful submission.
- Held drafts become invitation records without sending email.
- Acceptance never blocks admin approval.
- Retrying is application-idempotent. Do not claim mathematical exactly-once email across
  an external provider crash boundary.
- Submission alerts go to a deliverable assigned salesperson address plus deduplicated
  superadmins. Generated `.local` salesperson addresses are excluded.
- Owner lifecycle messages go to all active Hotel Owner accesses for the property.

## Owner screen

The Review page groups all setup sections by phase, shows status/finding badges, direct
Fix/View links, warnings, and staff/corporate invitation totals. In `pending_review` it is
read-only and remains reachable even though earlier steps are locked.

## Validation completed

- Focused onboarding group: 230 examples, 0 failures.
- `bin/test hotel_management`: 353 examples, 0 failures.
- RuboCop: no offenses.
- Brakeman, Bundle Audit, Importmap Audit, and Tailwind build passed.
- A later full parallel suite was stopped at the user's request after unrelated existing
  room-number factory and legacy expectation failures; system/browser coverage was not run.

Phase 11 is described in `PHASE_11_ADMIN_REVIEW.md`.
