# Onboarding — remaining work handover

Verified against the code on `feat/onboarding-shell` on 2026-08-13, after the Phase 10–11
implementation and the four review-workspace commits that followed it
(`870834310` … `34ce37fbb`). This is the current handoff; older phase proposals are
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
| 12 | Setup-hotel portal enforcement and rollout | Not started |
| 13 | Legacy lifecycle cleanup | Not started |

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

## Phase 12 — portal enforcement and rollout

The current guard protects writes only while `pending_review`. Phase 12 still needs the
broader setup-hotel experience:

- Redirect setup-hotel owners from normal portal HTML pages to the earliest setup section.
- Keep onboarding, safe reads, security/profile, support, uploads/form actions, and logout
  reachable.
- Define intentional superadmin, multi-hotel, and non-owner behaviour.
- Decide how existing non-live hotels map to `setup` versus `pending_review`.
- Decide whether legacy pending-review rows are grandfathered or revalidated.
- Roll out progressively after production data verification.

Do not add broad setup redirects without this rollout work.

## Phase 13 — legacy cleanup

`Onboarding::LifecycleCompatibility` still reads legacy setup statuses and maps hotel
`approved` to canonical `live`. Phase 13 must:

- migrate/remove legacy setup status writes;
- migrate hotel `approved` to `live` without touching unrelated approval domains;
- update factories, seeds, queries, jobs, reports, APIs, and booking eligibility;
- retire remaining obsolete onboarding URLs/messages;
- preserve submission, audit, invitation, and training history;
- decide whether one-year setup coverage becomes a maintained rolling horizon.

## Deferred channel-manager work

Phase 9 and the admin review intentionally stop at credential handover. Admin review shows
only channel name and credential presence. Provisioning, mapping, connection state, ARI
push, retry, and diagnostics remain a separate superadmin channel slice.

Carry-forward defect: several sync guards test
`hotel.preferred_channel_manager.blank?`, but explicit `undecided`/`none` values are
present. Test actual connectedness when building the superadmin slice.

## Validation record

Re-measured on 2026-08-13 at `34ce37fbb`, the tip of the branch:

- Onboarding-focused group — `spec/services/onboarding`, `spec/jobs/onboarding`, the two
  onboarding models, the two onboarding presenters, the four hotel-portal and admin
  onboarding request specs, and `spec/requests/admin/hotels_spec.rb`: 257 examples,
  0 failures.

Measured earlier, during Phase 10–11 implementation, and not re-run since the
review-workspace commits:

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
