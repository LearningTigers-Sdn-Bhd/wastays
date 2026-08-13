# Onboarding — remaining work handover

Verified against the code on branch `feat/onboarding-shell` on 2026-08-13 (44 commits
ahead of `main`, working tree clean). This file states what is actually built, what is
left, and where the traps are. Read `README.md` in this folder first for the shared
pattern; read `PLAN.md` for the phase scope authority.

Everything below was confirmed by reading the code, not by trusting the older docs. Where
an older doc disagrees with this file, this file is right.

## Verified state

| Phase | Sections | State |
|---|---|---|
| 0–3 | lifecycle, admin creation, shell | Complete |
| 4 | `property_profile`, `roles_permissions`, `staff_setup` | Complete |
| 5 | `taxes_fees`, `room_revenue` | Complete |
| 6 | `rooms` | Complete |
| 7 | `rates_availability` | Complete |
| 8 | `extra_charges`, `discounts`, `payment_methods`, `corporate_accounts` | Complete |
| 9 | `channel_manager` | Complete **as rescoped** — credential intake only |
| 10 | `review` + submission | **Not started** (parts pre-built, see below) |
| 11 | Admin review and launch | Not started |
| 12 | Portal enforcement and rollout | Not started |
| 13 | Legacy cleanup | Not started |

Twelve of the thirteen sections in `app/services/onboarding/section_catalog.rb` are listed
in `OnboardingController::IMPLEMENTED_SECTIONS`. Only `review` is missing, and it is the
one section that still runs on the shell's placeholder contract.

Phase 9 shipped deliberately smaller than its brief: OTA extranet credential intake
(`hotel_ota_credentials`, `Onboarding::SaveOtaCredentials`), no provisioning, no mapping,
no ARI push, no connection states. The rescope note at the top of
`PHASE_09_CHANNEL_MANAGER.md` records why and lists the superadmin work deferred out of
it. The rest of that file is the *original* larger scope, not a description of what exists.

## Phase 10 — what is already built

Do not rebuild these. They were landed early by the phases that owned the underlying data.

- `Onboarding::Readiness` — returns `Result(ready:, blocking_issues:, warnings:)` with
  `Finding(section_key:, severity:, message:)`. Treats any section carrying
  `decision_metadata["placeholder"]` as blocking, which is what stops a stub from being
  submitted today.
- `Onboarding::TransitionLifecycle` — enforces `setup -> pending_review`, re-runs
  `Readiness` server-side inside the guard, and writes the status change plus a `submitted`
  audit event in one transaction. Currently has **no production caller** — only specs.
- `Onboarding::DeliverInvitations` — turns staff and corporate drafts into real
  invitations, one transaction per draft, stamping `invitation_id` + `delivered_at` so a
  half-finished run is resumable and a retry sends nothing twice. Honours each draft's
  `send_invitation` switch: unsent drafts still become invitation records, distinguishable
  by a null `last_sent_at`. Also has **no production caller** — only specs.
- Read-only state — `OnboardingController#update` redirects when the hotel is
  `pending_review`, and the presenter exposes `read_only?`.

`IMPLEMENTATION_MAP.md` §8 item 11 still says staff drafts have no idempotent delivery
marker. That is now stale: `onboarding_staff_drafts` has the same `invitation_id` +
`delivered_at` marker and an `undelivered` scope. Correct that line when you touch the map.

## Phase 10 — what is left

1. **The `review` section itself.** Add `review` to `IMPLEMENTED_SECTIONS`, a
   `_review.html.erb` partial, a `prepare_section` branch, and a readiness presenter.
   Group findings by `SectionCatalog.fetch(key).phase`, distinguish blocking / warning /
   complete / skipped / needs attention, and link each finding to `onboarding_section_path`.
   `Readiness`'s messages are generic today ("Complete this required section.") — enrich
   them per section.
2. **A submission service** wiring `TransitionLifecycle` + `DeliverInvitations` together.
   The tension to resolve: the status transition must be atomic, but mail must not be
   enqueued inside that transaction. `DeliverInvitations` already keeps `deliver_later`
   outside its per-draft transaction, so the natural shape is: commit the transition, then
   run (or enqueue) delivery. Confirm with the user before building.
3. **Admin notification.** The admin queue populates itself from
   `Hotel.pending_review_onboarding`, so this is an extra signal, not the mechanism. Check
   what notification path the app already uses before adding one.
4. **Verify no section still carries `placeholder`.** Once `review` is implemented, a
   leftover placeholder anywhere is a silent, unexplained submission blocker.
5. **Verify every partial from phases 5–9 honours `@presenter.read_only?`.** This is the
   first phase where that state is actually reachable.

Test expectation: service specs (grouping, links, happy path, refusal when readiness fails,
retry sends nothing twice), request specs (review authorization, submit, read-only after
submission), and a system spec of the full owner path ending in submission. Phase 10 is an
integration milestone — running `bin/ci` here is justified.

## Phase 11 — admin review and launch

Nothing built. The existing admin surface is the **legacy** one and must not be mistaken
for it: `Admin::Hotels::OnboardingController` (`index`, `show`, `complete`, `save_period`)
drives training-session scheduling and `Admin::CompleteOnboarding`, which is the old
approval path. Its `index` already reads `Hotel.pending_review_onboarding`, so a submitted
hotel will appear there — with none of the new readiness detail.

To build: a setup summary showing section completion and readiness findings; Request
changes with selected sections and an explanation (this is the `pending_review -> setup`
transition, already allowed by `TransitionLifecycle`, event `changes_requested`); owner
notification and a `needs_attention` state; Approve & go live with a final server-side
readiness re-run (`pending_review -> live`, event `approved`); and alignment of the
existing suspend/reactivate paths with the simplified lifecycle.

Decide early whether Phase 11 extends the existing admin controller or replaces it — two
parallel approval paths reaching `live` by different routes is the failure mode here.

## Phase 12 — portal enforcement and rollout

Nothing built, by design: rule 5 in `README.md` forbids adding global redirects before
this phase. Requires redirecting setup-hotel owners from normal portal HTML pages to their
resume page, while keeping the onboarding allowlist, security routes, support, uploads,
form actions, and logout reachable. Explicit handling for `pending_review`, `live`, and
`suspended`; intentional superadmin access; confirmed multi-hotel and non-owner behaviour;
progressive rollout to new hotels first.

Do not start this before Phase 11 — enforcement with no admin path to launch traps every
hotel that submits.

## Phase 13 — legacy cleanup

Nothing built. The compatibility layer that makes cleanup possible is
`Onboarding::LifecycleCompatibility`: it folds five legacy setup statuses
(`registered`, `email_verified`, `profile_incomplete`, `rooms_incomplete`,
`inventory_incomplete`) into `setup`, and `approved` into `live`.

Scope check before planning: `Hotel::STATUSES` still declares all of them, and roughly
twenty files reference `approved` — though many are `RefundRequest` / `ArPaymentSubmission`
approvals, an unrelated meaning of the word. Separate the two before any find-and-replace.
Also in scope: the dashboard onboarding wizard, shared default-password messaging,
duplicate admin approval actions, legacy onboarding URLs, and factories/seeds/queries/
reports/jobs/APIs/public booking scopes. Preserve historical onboarding session and audit
data.

## Known defects carried forward

1. **Channel-manager sync guards test the wrong thing.** Every guard tests
   `hotel.preferred_channel_manager.blank?` (`app/models/room_type.rb:174` and others), but
   Phase 2 stores explicit `"undecided"` / `"none"` values, both of which are `present?`.
   Hotels that want no channel manager therefore enqueue sync jobs that die downstream on a
   missing mapping. Fix the guards to test *connectedness* when the superadmin channel
   slice is built.
2. **OTA credentials are write-only.** No UI reads `hotel_ota_credentials`. Until the
   superadmin slice lands, the rows an owner submits are visible to nobody in the product.

## Open product decisions still unresolved

From `PLAN.md` §"Open decisions", these still block the phases named:

| Decision | Blocks |
|---|---|
| Do training sessions remain a launch prerequisite, a warning, or independent? | 10, 11 |
| Do live hotels keep a read-only onboarding summary, or only an audit record? | 10, 11 |
| How do existing non-live hotels map to `setup` vs `pending_review`? | 12 |
| Are old `pending_review` submissions grandfathered, returned to setup, or revalidated? | 12 |
| Is one-year availability a one-time population or a rolling horizon? | 13 (and any coverage warning work) |
| Will a channel manager ever be mandatory for some plans? | superadmin channel slice |

Resolve each before its dependent phase; none of them blocks Phase 10's review page.

## Conventions the next session must keep

- One branch, sequential commits — not stacked branches. Current branch
  `feat/onboarding-shell`; confirm with the user whether to continue on it.
- Business logic in `app/services/onboarding/`, one verb-named class per file. Section
  state changes go through `Onboarding::UpdateSection` only — never write
  `onboarding_sections` rows directly.
- Reuse domain services; the onboarding domain orchestrates and presents, it does not fork
  rules. The only sanctioned onboarding-owned records are the queued invitation drafts.
- No defaults initialized as a page-visit side effect.
- Invalidate downstream by moving a section to `needs_attention` with an audit event —
  never by silently deleting referencing records.
- No skip buttons. Each optional section answers itself: an empty table is the decision,
  and the section's save service records it (`Onboarding::SkipOptionalSection`).
- The shell owns each step's heading; a section partial with its own `h2` is restating it.
- UI follows `DESIGN.md` — PanelsUI, semantic tokens, no native selects. Repeating records
  use `HotelPortal::Setup::RecordTable`.

```bash
bin/test hotel_management
```

```bash
bin/rubocop
```
