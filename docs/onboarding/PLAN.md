# Hotel Onboarding Delivery Plan

## Purpose

Deliver the integrated hotel onboarding flow incrementally. This work must not be attempted as one large change.

The authoritative product and presentation decisions are:

- `docs/onboarding/FLOW_DECISIONS.md`
- `docs/onboarding/DESIGN_DECISIONS.md`
- Root `DESIGN.md` for the portal UI contract

Existing hotel, tax, room, rate, financial, staff, corporate account, and channel-manager services remain the source of domain behaviour. The onboarding domain orchestrates and presents those capabilities; it must not fork their business rules.

Per-phase handoff briefs live in `docs/onboarding/handoffs/`, starting with `docs/onboarding/handoffs/README.md`. They exist so a session with no prior context can pick up a single phase.

**Current position (2026-08-13): phases 0–11 implemented, phase 12 next.**
`docs/onboarding/handoffs/REMAINING_WORK.md` holds the verified branch state and the scope
of phases 12–13; where it disagrees with an older phase brief, it is right.

## Delivery principles

1. Ship narrow vertical slices.
2. Keep the existing hotel portal functional during migration.
3. Introduce the new flow behind an explicit rollout mechanism until readiness and redirect rules are complete.
4. Give each onboarding page one responsibility.
5. Reuse existing domain services and validations.
6. Add compatibility handling before removing legacy statuses.
7. Validate each phase with focused request, service, component, and system coverage.
8. Do not enable automatic portal redirects until escape routes and all required onboarding endpoints are proven.

## Phase 0: Discovery and dependency map — Complete (2026-08-12)

Before implementation:

- Inventory every existing hotel status read and write.
- Identify every place where `approved` and `live` are treated differently or together.
- Inventory current hotel creation fields and confirm subscription plan support at creation.
- Map existing profile, roles, staff, taxes, room revenue, rooms, rate plans, inventory, extra charges, discounts, payment methods, corporate accounts, and channel-manager services.
- Map plan-gated features, especially role-based access control.
- Decide how current hotels map into the simplified lifecycle.
- Decide whether existing onboarding sessions and training remain part of admin review.
- Confirm how one-year local availability aligns with channel-manager sync horizons.
- Record the unresolved product decision about future channel-manager mandatory status.

Deliverable: a verified implementation map and migration matrix, with no user-visible behaviour change.

## Phase 1: Lifecycle and onboarding foundation — Complete (2026-08-12)

Introduce the foundation without redirecting users yet:

- Onboarding progress representation separate from `Hotel#status`
- Stable section identifiers and ordering
- Section states: not started, in progress, complete, skipped, needs attention
- Completion timestamps and optional decision metadata
- Resume-page resolver
- Prerequisite and dependency map
- Readiness result with blocking issues and warnings
- Compatibility layer for legacy hotel statuses
- Audit trail for completion, skip, invalidation, submission, requested changes, and approval

Define the target lifecycle transition rules:

```text
setup -> pending_review -> live -> suspended
```

Deliverable: domain foundation covered by service/model tests, unused by production routing.

## Phase 2: Admin creation vertical slice — Complete (2026-08-12)

Update admin hotel creation as a self-contained slice:

- Restrict creation responsibility to account and platform-level choices.
- Add subscription plan selection during creation.
- Preserve immutable sell-mode selection.
- Support preferred channel manager and undecided state.
- Add Cancel, Create only, and Create & onboard actions.
- Create new hotels in `setup`.
- Add secure owner activation rather than exposing a shared default password.
- Add onboarding handoff/tracker feedback for admins.

`Create only` does not send the owner onboarding invitation. `Create & onboard` does.

Deliverable: admins can create a setup hotel safely; existing portal users are not yet globally redirected.

## Phase 3: Onboarding shell and navigation — Complete (2026-08-12)

Build the dedicated experience before adding all forms:

- Hotel-scoped onboarding routes
- Dedicated onboarding layout
- Navbar without the operational sidebar
- Six-phase progress navigation
- Local substep navigation
- Current-step and resume resolution
- Backward navigation
- Locked future-step handling
- Save draft and Save & continue contracts
- Optional-section decision contract (delivered as a Skip for now button, since retired — an optional section now answers itself when the owner continues from an empty table)
- Pending-review read-only state
- Changes-requested presentation
- Responsive and accessible navigation behaviour

Use placeholder section summaries only where required to validate navigation; do not duplicate domain forms prematurely.

Deliverable: an owner can activate, enter the onboarding shell, navigate allowed steps, and resume reliably.

## Phase 4: Property and team slice — Complete (2026-08-12)

Deliver complete pages for:

1. Property profile
2. Roles and permissions review
3. Draft staff setup

Requirements:

- Reuse the existing profile/photo services.
- Present seeded role presets read-only and require confirmation.
- Respect subscription-plan behaviour while allowing preset review.
- Store staff entries without sending invitations.
- Require an explicit staff configuration or `No additional staff for now` decision.
- Add page completion rules and final summaries.

Deliverable: the Property and Team phases are production-ready and independently testable.

## Phase 5: Financial foundation slice — Complete (2026-08-12)

Deliver:

1. Taxes and fees
2. Room revenue configuration and tax assignment

Requirements:

- Reuse existing tax and transaction configuration behaviour.
- Ensure default financial records are initialized deliberately rather than as a side effect of visiting an index page.
- Support system taxes and custom taxes/fees.
- Require explicit tax confirmation.
- Require valid room-revenue configuration.
- Invalidate room revenue and dependent commercial sections when relevant taxes change.

Deliverable: a hotel can establish its financial foundation before configuring products.

## Phase 6: Rooms slice — Complete (2026-08-12)

Deliver room setup:

- Excel-like room-type table with inline add/edit/remove
- Quantity and occupancy rules
- Conditional room-number requirements
- Amenities and room-number action sheets
- Smoking and pet policies
- Completion contract
- Dependency invalidation when rooms or capacities change

Reuse existing room save services. Do not create onboarding-only room records. Room
descriptions, photos, room groups, and all pricing remain outside this slice; Phase 7 owns
onboarding pricing, while optional descriptive details remain in regular Settings.

Deliverable: at least one operationally valid room type can be completed through onboarding.

## Phase 7: Pricing and one-year availability slice — Complete (2026-08-12)

Deliver separate sell-mode experiences.

### Per room

- Default room rate
- Base occupancy
- Extra-adult and extra-child pricing
- Rate-plan assignment

### Per pax

- Occupancy matrix sized to the hotel's highest supported occupancy
- Per-room disabled cells above supported occupancy
- Occupancy change warnings
- Child age bands configured once per rate plan
- Responsive one-room-at-a-time mobile experience

### Availability

- Bulk start and end dates, defaulting to one year
- Weekday/weekend rules
- Quantities and open/closed state
- Exceptions
- Coverage calculation
- Expiry warning and extension path

Use existing rate-plan and inventory services, extending their shared domain APIs only where the onboarding bulk workflow requires it.

Deliverable: a configured room has valid sell-mode pricing and one year of sellable rates and inventory.

## Phase 8: Commercial configuration slices — Complete (2026-08-13)

Deliver these as separate, independently reviewable pages or sub-phases:

1. Extra charges
2. Discounts
3. Payment methods
4. Corporate accounts

Requirements:

- Taxes are available for extra-charge assignment.
- Discounts can target established eligible charge codes.
- Payment surcharges can reference existing extra charges.
- At least one usable payment method is required.
- Extra charges, discounts, and corporate accounts record an explicit decision when left empty. Delivered without a skip button: continuing from an empty table is the answer, and the section's own save service records it. A separate control would ask the same question twice.
- Corporate invitations remain queued until submission and do not block on acceptance.
- Dependency invalidation warns instead of silently deleting references.

Deliverable: the hotel's commercial and payment setup can be completed without entering the normal settings portal.

## Phase 9: Channel manager slice — Complete as rescoped (2026-08-13)

Rescoped during delivery to **credential intake only**, matching how the client already works: they collect OTA extranet logins on a spreadsheet and connect the channels themselves afterwards. The owner-facing connection flow was cut.

Delivered:

- Preferred provider display, never written — the admin's choice is read-only here
- OTA extranet credential intake (`hotel_ota_credentials`): channel, property ID, username, password, market manager contact, with username and password encrypted at rest and passwords write-only from the portal
- Continuing from an empty table records `no_channel_manager_now`, so the section resolves either way
- Clear distinction between local readiness and external synchronization readiness — the section never blocks launch

Deferred to a later superadmin slice, not delivered here:

- Property provisioning, room and rate-plan mapping, initial rate and availability push
- Connection states, retry, and diagnostics
- Plan gating for `manage_40_otas`
- Any admin access to actual credential values. Phase 11 review shows only channel name
  and credential presence from the safe submission snapshot.

Carry-forward defect: every sync guard tests `hotel.preferred_channel_manager.blank?` (`app/models/room_type.rb:174` and others), but Phase 2 stores explicit `"undecided"` / `"none"` values, both of which are `present?`. Hotels wanting no channel manager therefore enqueue sync jobs that die downstream on a missing mapping. Fix the guards to test connectedness when the superadmin slice is built.

Deliverable: an owner hands over the logins their channels need and reaches review either way, with local setup unaffected.

## Phase 10: Review, submission, and invitations — Complete

Delivered:

- Group findings by phase.
- Distinguish blocking issues, warnings, complete, skipped, and needs attention.
- Link each finding to its owning page.
- Re-run readiness server-side on submission.
- Create an immutable, secret-free submission snapshot and durable outbox effects.
- Process queued staff and requested corporate invitations only after successful submission.
- Change the hotel to `pending_review` atomically with submission records.
- Make submitted onboarding read-only.
- Notify admins.

Delivery is application-idempotent and retryable. Exact-once external email is not claimed.

Deliverable: an owner can complete and submit onboarding safely.

## Phase 11: Admin review and launch — Complete

Delivered through the canonical admin onboarding page:

- Admin setup summary
- Section completion and readiness findings
- Request changes with selected sections and explanation
- Owner notification and needs-attention state
- Approve & go live with final server-side readiness validation
- Audit trail
- Existing suspension/reactivation alignment with the simplified lifecycle
- Immutable approved snapshot retained after launch
- Training retained as informational and non-blocking
- Legacy completion removed; generic approval limited to suspended reactivation

Deliverable: admins can request targeted corrections or launch a ready hotel.

## Phase 12: Portal enforcement and rollout

Only after all required owner flows exist:

- Redirect setup-hotel owners from normal hotel portal HTML pages to their resume page.
- Keep the onboarding allowlist, security routes, support, uploads, form actions, and logout reachable.
- Handle pending-review, live, and suspended routing explicitly.
- Keep superadmin/admin access intentional and audited.
- Confirm multi-hotel user behaviour.
- Confirm non-owner behaviour if a user has access before launch.
- Roll out progressively to new hotels first.
- Migrate existing onboarding hotels after data verification.

Deliverable: the onboarding path becomes the enforced default for setup hotels.

## Phase 13: Legacy cleanup

`Onboarding::LifecycleCompatibility` is what makes this possible: it folds five legacy setup statuses (`registered`, `email_verified`, `profile_incomplete`, `rooms_incomplete`, `inventory_incomplete`) into `setup`, and `approved` into `live`. `Hotel::STATUSES` still declares all of them.

Scope trap: roughly twenty files reference `approved`, but many are `RefundRequest` and `ArPaymentSubmission` approvals — an unrelated meaning of the word. Separate the two before any find-and-replace.

After rollout is stable:

- Remove legacy onboarding-stage status transitions.
- Migrate or remove `approved` in favour of `live`.
- Remove obsolete dashboard onboarding wizard behaviour.
- Remove shared default-password messaging and paths.
- Consolidate duplicate admin approval/onboarding completion actions.
- Redirect or retire legacy onboarding URLs.
- Update factories, seeds, queries, reports, jobs, APIs, and public booking scopes.
- Preserve historical onboarding session and audit data as required.

Deliverable: one lifecycle, one onboarding progress model, and no parallel legacy flow.

## Validation expectations per slice

Each slice should include proportionate validation:

- Focused service/model specs for completion and dependencies
- Request specs for authorization, navigation, save, skip, and redirects
- Component/view specs for progress and step states
- System specs for the critical owner path
- Accessibility checks for keyboard, labels, errors, and progress state
- Responsive review for mobile tables and per-pax pricing
- Regression coverage for existing regular settings backed by reused services

Run the relevant project test domain and RuboCop for each implementation slice. Reserve the complete CI suite for integration milestones and final rollout readiness.

## Open decisions

The following remain intentionally unresolved:

| Decision | Blocks |
|---|---|
| Whether a channel manager will eventually become mandatory for some plans or properties. | The deferred superadmin channel slice |
| Whether one-year availability remains a one-time initial population or becomes a maintained rolling horizon. | 13, and any coverage-expiry work |
| How existing non-live hotels map to `setup` versus `pending_review` during migration. | 12 |
| Whether old `pending_review` submissions are grandfathered, returned to setup, or revalidated under the target checks. | 12 |

Resolved during delivery:

- **Corporate and staff invitation delivery:** durable `OnboardingDelivery` effects are
  unique and retryable; per-draft invitation links prevent duplicate application work.
  Exact-once external email is intentionally not claimed.
- **Training and launch:** training is visible but independent and never blocks launch.
- **Post-launch summary:** live hotels retain the immutable approved submission snapshot.
- **Owner-facing channel-manager connection states.** Phase 9's rescope removed the question: the owner hands over credentials, and connection states belong to the deferred superadmin slice.

Resolve each open decision before its dependent delivery phase; do not block unrelated earlier slices.
