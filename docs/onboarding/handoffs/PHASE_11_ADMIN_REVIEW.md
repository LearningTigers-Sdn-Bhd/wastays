# Phase 11 — Admin review and launch

Implemented on `feat/onboarding-shell` on 2026-08-13 together with Phase 10, then
reorganized into the current workspace by `4717dceec`, `773508d71`, `7f868efd5`, and
`34ce37fbb`. This file describes the delivered page, not the first cut.

## Where the queue lives

There is no onboarding tracker page. `4717dceec` deleted `onboarding#index`, its table
partial, and its two Stimulus controllers. Hotels awaiting review are the `pending_review`
filter on the admin hotels list: `Admin::Hotels::IndexPresenter` supplies the status tab
counts, the extra pending-review columns, and each row's `review_path`.

## Canonical review path

`/admin/hotels/:id/onboarding` is the only onboarding review page. It is a full-height
workspace with one scroller around the tab content.

The header carries the hotel name, lifecycle badge, location, onboarding period, and an
Actions menu: Edit onboarding period always, plus Request changes and Approve and go live
when a pending submission exists and the hotel is still `pending_review`.

Three tabs are declared in `Admin::Hotels::OnboardingController::TAB_LABELS` and reached
through `GET onboarding` (Overview) and `GET onboarding/:tab`. Each tab loads only its own
data:

- **Overview** — a launch-readiness alert, metric cards, the Setup review table, and the
  submitted-snapshot tables (Property submitted, Rooms submitted, Commercial setup,
  Handover). Handover covers invitation delivery counts and OTA channel names with
  credential presence only. Built by `Admin::Hotels::OnboardingOverviewPresenter` over
  `Onboarding::SnapshotSummaryPresenter`, plus current readiness and whether the current
  configuration digest still matches the submitted one.
- **History** — onboarding audit events, newest first.
- **Training** — training sessions, clearly informational and non-blocking.

The onboarding period is editable here: `POST save_onboarding_period` validates both dates
and returns to the tab it was invoked from.

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
- The onboarding tracker page and its Complete action were removed entirely, along with
  `spec/requests/admin/onboarding_tracker_spec.rb`. Admins reach review from the hotels
  list instead.
- Generic admin approval redirects `pending_review` hotels to the canonical review page.
- `Admin::Hotels::ApproveService` is now only for suspended-property reactivation and
  restores/falls back to `live`, never a new onboarding `approved` hotel status.

## Locked product decisions

- Training is independent and never blocks launch.
- Live hotels retain their approved onboarding snapshot.
- Legacy hotel statuses remain readable through compatibility code until Phase 13, but no
  new onboarding action writes the hotel status `approved`.
