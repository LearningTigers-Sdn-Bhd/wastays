# Phase 9 — Channel manager slice

Read `docs/onboarding/handoffs/README.md` first for the shared pattern and rules.

## Rescoped, 2026-08-13 — what shipped

The owner-facing slice below was cut down to **credential intake only**, matching
how the client already works: they collect OTA extranet logins on a spreadsheet
and connect the channels themselves afterwards.

What shipped: `hotel_ota_credentials` (channel, property ID, username, password,
market manager contact — username and password encrypted at rest),
`Onboarding::SaveOtaCredentials`, and the section's record table. Continuing from
an empty table records `no_channel_manager_now`; there is no separate skip
button. The admin's `preferred_channel_manager` is only ever displayed, never
written. Passwords are write-only from the hotel portal — never rendered back
into a field, and redacted from a failed submission.

What did **not** ship, and is superadmin work for later: provisioning, room and
rate-plan mapping, the initial ARI push, diagnostics, retry, connection states,
plan gating, and any admin-side view of these rows. Until that lands the table is
write-only — no UI reads it.

One defect found and deliberately left alone: every sync guard tests
`hotel.preferred_channel_manager.blank?` (`app/models/room_type.rb:174` and
others), but Phase 2 stores explicit `"undecided"` / `"none"` values, both of
which are `present?`. Hotels that want no channel manager therefore enqueue sync
jobs that die downstream on a missing mapping. Fix the guards to test
connectedness when the superadmin slice is built.

The rest of this brief is the original, larger scope. Treat it as the plan for
that later work, not as a description of what exists.

## Goal

Make the `channel_manager` section real. It runs **last** among configuration phases,
after local rooms, rates, and inventory are stable, and it must be safe to skip.

`PLAN.md` §"Phase 9" is the scope authority.

## Prerequisite

`corporate_accounts`, and transitively everything before it. Do not attempt this phase
before Phase 7 — external sync of incomplete local rates is the failure mode this
ordering exists to prevent.

## Deliverables

- Preferred provider display
- States: decision pending, none, skip, connect, connected, failed
- Prerequisite checks
- Property provisioning
- Room and rate-plan mapping
- Initial rate and availability push
- Retry and diagnostics
- A clear distinction between **local readiness** and **external synchronization readiness**

That last point is the design crux: a hotel can be fully launch-ready locally with no
channel manager connected. The section is optional (`section_catalog.rb:19`) and must not
block launch while the agreed policy remains optional.

## Existing code to reuse

| Need | Reuse |
|---|---|
| Admin-side Channex onboarding | `Admin::Hotels::OnboardChannexService` |
| Provider onboarding | `ChannelManagers::OnboardingService` |
| Mapping diagnostics | `ChannelManagers::DiagnoseMappingService` |
| Mapping repair | `ChannelManagers::RepairMappingService` |
| Sync orchestration | `ChannelManagers::SyncOrchestrator` |
| Rate/ARI push | `ChannelManagers::SyncRatePlanAri` |
| Full refresh | `ChannelManagers::FullRefreshService` |
| Adapter | `ChannelManagers::ChannexAdapter` |
| Disconnect | `ChannelManagers::DisconnectService` |

Existing specs worth reading first: `spec/services/channel_managers/onboarding_service_spec.rb`
and `spec/services/channel_managers/channex_onboarding_flow_spec.rb`.

## Preferred provider representation

`hotels.preferred_channel_manager` is a single nullable string (`db/schema.rb:1563`).
There is no separate "undecided" field — null currently means both "not chosen" and
"chose none". Phase 2 added preferred-provider and undecided handling at creation; check
what shape it actually landed in before designing the states, because this section needs
to distinguish at least:

- decision pending (admin set no preference)
- none (owner explicitly wants no channel manager)
- skipped for now (owner will decide later)
- connect in progress / connected / failed

`IMPLEMENTATION_MAP.md` §8 item 7 lists this representation as unresolved. If Phase 2 did
not settle it, settle it here and record the decision.

**Preserve the preferred provider when connection is skipped.** Skipping must not clear
the admin's provider choice.

## Sync horizon mismatch

`ChannelManagers::FullRefreshService` uses a 500-day horizon while onboarding populates one
year of local availability. Do not widen the local population to match, and do not treat a
500-day external push as evidence of local coverage. Define the initial push against
whatever coverage Phase 7 actually established.

## Plan gating

Admin channel-manager onboarding is gated by the `manage_40_otas` feature
(`app/controllers/admin/hotels/channel_managers_controller.rb`). Decide how the owner-facing
onboarding section behaves for a hotel whose plan lacks that feature — most likely present
the section as unavailable-by-plan and auto-resolve it rather than blocking submission.
Confirm with the user.

## Failure handling

Connection failures are expected and must not corrupt local setup or strand the section in
an unresolvable state. A failed connection should:

- record the failure with diagnostics the owner can read
- offer retry
- still allow skipping and proceeding to review

## Open decision

Whether a channel manager eventually becomes **mandatory** for some plans or properties is
explicitly unresolved (`PLAN.md` §"Open decisions" item 1). Build for optional; do not
hard-code an assumption that forecloses mandatory later.

## Tests

- Service specs: each state transition, prerequisite checks, skip preserving preferred
  provider, failure and retry
- Request specs: section availability, skip, connect action authorization
- Stub the external adapter — no live Channex calls in tests
- System spec: owner skips the channel manager and reaches review

```bash
bin/test channels
```

## Done when

An owner can reach the channel manager step, see the admin's preferred provider, connect
or explicitly decline, recover from a failed connection, and proceed to review either way
— with local readiness unaffected by the outcome.
