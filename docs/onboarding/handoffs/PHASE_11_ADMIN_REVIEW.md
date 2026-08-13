# Phase 11 — Admin review and launch

Implemented on `feat/onboarding-shell` on 2026-08-13 together with Phase 10.

## Canonical review path

`/admin/hotels/:id/onboarding` is the only onboarding review page. It shows:

- immutable submitted property, room/rate, and commercial data;
- current readiness and whether the current configuration digest still matches;
- submission time and submitter;
- invitation delivery counts;
- OTA channel names and credential presence only;
- onboarding audit history;
- training sessions, clearly informational and non-blocking.

## Request changes

`POST /admin/hotels/:id/onboarding/request_changes` uses
`Onboarding::RequestChanges`.

- The PanelsUI sheet requires at least one of the twelve setup sections and an explanation.
- The service locks a pending-review hotel.
- Selected sections and Review move to `needs_attention` through `UpdateSection`.
- Each selected section gets a `changes_requested` audit event.
- The hotel returns to `setup`, the submission becomes `changes_requested`, and owner email
  effects are created atomically.
- Resume navigation selects the earliest affected section.
- Existing invitations are not deleted or resent.

## Approve and launch

`POST /admin/hotels/:id/onboarding/approve` uses
`Onboarding::ApproveOnboarding`.

- The service locks the hotel and requires a pending submission.
- It reruns current readiness and rebuilds the current configuration digest.
- Approval is blocked when readiness fails or the digest differs from the immutable
  submitted version.
- Success records the reviewer and audit event, activates the account, transitions directly
  to `live`, marks the submission `approved`, and creates owner notification effects.
- The approved snapshot remains available after launch. Later operational changes belong
  in normal Settings and do not rewrite it.

## Removed parallel paths

- `Admin::CompleteOnboarding` and its route were removed.
- The tracker no longer has a direct Complete action; it links to Review.
- Generic admin approval redirects `pending_review` hotels to the canonical review page.
- `Admin::Hotels::ApproveService` is now only for suspended-property reactivation and
  restores/falls back to `live`, never a new onboarding `approved` hotel status.

## Locked product decisions

- Training is independent and never blocks launch.
- Live hotels retain their approved onboarding snapshot.
- Legacy hotel statuses remain readable through compatibility code until Phase 13, but no
  new onboarding action writes the hotel status `approved`.
