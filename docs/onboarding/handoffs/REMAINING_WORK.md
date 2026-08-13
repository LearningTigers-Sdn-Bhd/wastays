# Onboarding — remaining work handover

Verified against the code on `feat/onboarding-shell` on 2026-08-13, after phases 12–13
(`af9a06a1b` … `d43c8b914`). This is the current handoff; older phase proposals are
historical when they disagree with it.

## Current status

| Phase | Scope | State |
|---|---|---|
| 0–3 | lifecycle, admin creation, shell | Complete |
| 4 | property, roles, staff | Complete |
| 5 | taxes and room revenue | Complete |
| 6 | rooms | Complete |
| 7 | rates and availability | Complete |
| 8 | commercial setup | Complete |
| 9 | OTA credential intake | Complete as rescoped |
| 10 | Review, submission, snapshot, durable deliveries | Complete |
| 11 | Admin review, targeted changes, launch | Complete |
| 12 | Setup-hotel portal enforcement and rollout | Complete, rollout pending |
| 13 | Legacy lifecycle cleanup | Complete |

All thirteen section keys are real entries in `OnboardingController::IMPLEMENTED_SECTIONS`.
Review is not a placeholder and never blocks itself.

## Phases 10–11 — do not rebuild

Read `PHASE_10_REVIEW_SUBMISSION.md` and `PHASE_11_ADMIN_REVIEW.md` for full contracts.

- `OnboardingSubmission` is immutable submission history with a versioned, secret-free
  snapshot, readiness snapshot, configuration digest, actors, and review result.
- `OnboardingDelivery` is the durable application outbox. A recurring job retries failed
  effects and recovers work left processing by a stopped worker.
- `Onboarding::SubmitOnboarding` and the singular owner submission route are the only owner
  submission path.
- `Onboarding::RequestChanges` and `Onboarding::ApproveOnboarding` are the only onboarding
  review mutations. `/admin/hotels/:id/onboarding` is the canonical admin page, and the
  review queue is the `pending_review` filter on the admin hotels list. The separate
  onboarding tracker page is gone.
- Pending review is write-protected in the hotel portal. `protect_pending_review_writes!`
  blocks every non-GET request except `HotelPortal::UserProfilesController` and
  `HotelPortal::OnboardingSubmissionsController`. Reads stay reachable; so does logout,
  which is not a hotel-portal controller.
- Training is visible but independent and never blocks launch.
- The approved snapshot remains immutable after launch.
- `Admin::CompleteOnboarding`, dashboard direct submission, tracker completion, and legacy
  completion routes were removed. Generic approval is only for suspended reactivation.

Important regression rule: confirmation and readiness must both use
`ConfirmRolePresets.permission_fingerprint`. JSON key order affects the digest. The preset
order is `hotel_owner`, `general_manager`, `front_desk`, `housekeeper`; independently
sorting the roles alphabetically caused a successfully saved section to remain falsely
stale.

## Phase 13 — legacy cleanup (done)

`Hotel::STATUSES` is now exactly `setup`, `pending_review`, `live`, `suspended`, and the
model validates against it, so the legacy vocabulary cannot come back.
`NormalizeHotelLifecycleStatuses` backfilled `hotels.status` and
`hotels.pre_suspension_status` together — the suspend/reactivate round trip stashes a raw
status in the latter. It reports its row counts, is idempotent, and is deliberately
irreversible: `live` cannot be told apart from a row that was already live.

Public bookability moved from `["approved", "live"]` to `"live"` in the same commit as the
backfill. The two are only correct together; never split them.

`Onboarding::LifecycleCompatibility` is gone. Its nine call sites compare status directly.

Also removed: the wizard-era `complete_profile!` / `complete_policies!` / `complete_rooms!`
writers, the three `*_completed?` predicates they fed, and the "Back to onboarding" nudges
those drove on room types, profile, and inventory.

Still open from the original Phase 13 list: whether one-year setup coverage becomes a
maintained rolling horizon.

## Phase 12 — portal enforcement (built, not rolled out)

`enforce_setup_lock!` in `HotelPortal::BaseController` keeps a `setup` hotel inside
onboarding. It runs before `protect_pending_review_writes!`, which is unchanged — one guard
per status, no overlap.

- Whoever passes `HotelPolicy#update?` is redirected to
  `Onboarding::ResumePageResolver`'s section. That resolver is the single source of "where
  did they leave off"; do not add a second rule.
- Everyone else lands on `HotelPortal::SetupLocksController#show`. That path is close to
  unreachable now that invitations wait for approval; it exists for staff accounts that
  predate the change.
- Superadmins are exempt so they can inspect a property mid-setup.
- `SETUP_LOCK_EXEMPT` lists what stays reachable: onboarding, submissions, sessions, the
  user's own profile, and the explainer. Logout is not a hotel-portal controller.

**Rollout is the remaining work.** `hotels.setup_lock_enabled` defaults to false, so nothing
changed on deploy. An admin turns it on per property from the Actions menu on
`/admin/hotels/:id/onboarding`. Enable it on a real setup property, confirm the owner and a
staff member land where they should, then widen.

Two decisions from the original Phase 12 list were answered by Phase 13 rather than by the
guard: existing non-live hotels map to `setup` or `pending_review` by the backfill, and
pending-review rows were normalized rather than grandfathered.

## Invitation timing

Staff and corporate invitations are created on **approval**, not submission
(`CreateDeliveries.for_approval`). Submitting notifies administrators only. Inviting at
submission meant a reviewer who requested changes had already introduced people to a
property that was not open. Draft-level idempotency is unchanged, so a resubmitted property
still invites each contact exactly once.

## Deferred channel-manager work

Phase 9 and the admin review intentionally stop at credential handover. Admin review shows
only channel name and credential presence. Provisioning, mapping, connection state, ARI
push, retry, and diagnostics remain a separate superadmin channel slice.

Carry-forward defect: several sync guards test
`hotel.preferred_channel_manager.blank?`, but explicit `undecided`/`none` values are
present. Test actual connectedness when building the superadmin slice.

## Validation record

Measured on 2026-08-13 at `d43c8b914`, after phases 12–13. Scoped runs only, at the user's
instruction — no full-suite run:

- Onboarding group plus the new setup-lock and migration specs: 278 examples, 0 failures.
- Lifecycle group — `spec/models/hotel_spec.rb`, both hotel queries, booking availability
  and quoting, the public hotels API, room-type saving, hotel creation, and
  `spec/migrations/normalize_hotel_lifecycle_statuses_spec.rb`: 129 examples, 0 failures.
- RuboCop clean on the diff.

**Not verified:** the Phase 13 sweep rewrote `status: "approved"` to `status: "live"` across
75 spec files in domains the scoped runs above do not touch. Run `bin/test all` before
merging if that matters.

Brakeman reports one Medium "Dynamic Render Path" on
`app/views/admin/hotels/onboarding/show.html.erb`. It predates this work — the flagged
render line is unchanged since `34ce37fbb` — and the tab param is route-constrained to
`history|training`.

Measured earlier, during Phase 10–11 implementation, and not re-run since:

- RuboCop, Brakeman, Bundle Audit, Importmap Audit, and Tailwind build passed.
- `bin/test hotel_management`: 353 examples, 0 failures. Note that this domain contains no
  onboarding specs; it was run as a regression check, not as onboarding coverage.
- The broad parallel suite was stopped at the user's request after unrelated existing
  room-number factory and legacy expectation failures. System/browser tests were not run.

## Conventions to keep

- Business logic stays in verb-named services under `app/services/onboarding/`.
- Section state changes go through `Onboarding::UpdateSection`.
- Reuse real domain services and records; do not add shadow rooms/rates/inventory.
- Invalidate downstream state with `needs_attention` and an audit event; do not silently
  delete dependent records.
- Follow `DESIGN.md`, PanelsUI, semantic tokens, and `Setup::RecordTable`.
- Preserve immutable submission snapshots and never serialize tokens or OTA secrets.
