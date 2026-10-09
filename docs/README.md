# Documentation index

Documents are grouped by purpose. Authored plans, checklists, and decision records
remain available; the historical records retain their original dates and results.

## How to read these documents

- Read only the documents relevant to the current task.
- Follow your local `AGENTS.md` or `CLAUDE.md` when present. These files are Git-ignored and remain developer-specific.
- [DESIGN.md](../DESIGN.md) indexes the numbered portal and PDF rule files in `.ai/design/`.
- The checked onboarding summary is [CURRENT_BEHAVIOR.md](onboarding/CURRENT_BEHAVIOR.md).
- A proposal records intended work. Its presence does not mean the work is outstanding or authorize changes.
- A checklist or handover reports the state at its stated date and branch.
- A historical snapshot can contain renamed files and superseded decisions. Read current code before using it for a fix.
- Documentation review here does not confirm production state or repeat historical test runs.

## Onboarding

Current behavior, product decisions, and dated phase records.

- [Current onboarding behavior](onboarding/CURRENT_BEHAVIOR.md)
- [Hotel Onboarding Design Decisions](onboarding/DESIGN_DECISIONS.md)
- [Hotel Onboarding Flow Decisions](onboarding/FLOW_DECISIONS.md)
- [Hotel onboarding implementation map (Phase 0)](onboarding/IMPLEMENTATION_MAP.md)
- [Hotel Onboarding Delivery Plan](onboarding/PLAN.md)
- [Phase 6 — Rooms slice](onboarding/handoffs/PHASE_06_ROOMS.md)
- [Phase 7 — Pricing and one-year availability slice](onboarding/handoffs/PHASE_07_PRICING_AVAILABILITY.md)
- [Phase 8 — Commercial configuration slices](onboarding/handoffs/PHASE_08_COMMERCIAL.md)
- [Phase 9 — Channel manager slice](onboarding/handoffs/PHASE_09_CHANNEL_MANAGER.md)
- [Phase 10 — Review, submission, and invitations](onboarding/handoffs/PHASE_10_REVIEW_SUBMISSION.md)
- [Phase 11 — Admin review and launch](onboarding/handoffs/PHASE_11_ADMIN_REVIEW.md)
- [Onboarding phase handoffs — shared context](onboarding/handoffs/README.md)
- [Onboarding — remaining work handover](onboarding/handoffs/REMAINING_WORK.md)

## Guest Concierge

Guest requirements, access flow, theme, and layout contracts.

- [Guest Concierge Flow](guest-concierge/FLOW.md)
- [GuestUI Layout Contract](guest-concierge/LAYOUTING.md)
- [Guest Concierge Requirements](guest-concierge/REQUIREMENTS.md)
- [GuestUI Theme Contract](guest-concierge/THEME.md)

## AI Concierge

Conversation milestones and recorded delivery status.

- [AI Concierge Sales Conversation Milestones](ai-concierge/ai-concierge-sales-conversation-milestones.md)

## Folios and financial documents

Active service conventions, invoicing decisions, and delivery proposals.

- [Documents and Invoicing Plan](folios/DOCUMENTS_INVOICING_PLAN.md)
- [Folio Actions — Sheet family proposal](folios/folio-actions-sheet-proposal.md)
- [Folio service verbs](folios/folios-service-verbs.md)
- [Folios / Bookings Service Reorg & Refactor Proposal](folios/folios-services-reorg-proposal.md)

## Rates and inventory

Product explanations, roadmap, and technical handover.

- [Rates and inventory — current status and roadmap](rates/RATE_SETTINGS_PHASES.md)
- [Rate plans and rate inventory — technical handover](rates/rate-plan-and-inventory-handover.md)
- [Rate plans in plain English](rates/rate-plans-in-plain-english.md)

## Rooms

Physical-room research and milestone records.

- [Physical Rooms: Research and Planning for Milestones 0 to 3](rooms/room-groups-physical-rooms-0-3-research.md)
- [Room Groups and Physical Rooms Milestones](rooms/room-groups-physical-rooms-milestones.md)

## Accounts

Account-unification progress record.

- [Agent Account Unification — Progress Tracker](accounts/agent-account-unification.md)

## Payments and localisation

Authored TA payment decisions and the dated feature checklist.

- [Checklist: TA payments, attribution, Chinese, and four fixes](payments/feature-and-bugfix-checklist.md)
- [Travel agent payments, attribution, and a Chinese version](payments/ta-payments-and-localisation.md)

## Requests

Requests-board technical handover.

- [Requests board — handover](requests/REQUEST_BOARD_HANDOVER.md)

## Housekeeping

Request and task proposal.

- [Housekeeping Tasks — Audit & Remediation Proposal](housekeeping/HOUSEKEEPING_REQUEST_PROPOSAL.md)

## Guest registration

Tablet-signing spike and technical constraints.

- [Signing a registration card on a front-desk tablet](guest-registration/registration-card-tablet-signing.md)

## Integrations

eZee import, WhatsApp relay contract, and e-invoice integration plan.

- [E-Invoice Integration Plan](integrations/e-invoice-integration-plan.md)
- [Importing future reservations from eZee](integrations/ezee-reservation-import.md)
- [The WhatsApp relay contract](integrations/whatsapp-relay-contract.md)

## Maintenance

Pagination migration record and RSpec reporting proposals.

- [Pagination migration proposal](maintenance/pagination-migration-proposal.md)
- [RSpec Error Consolidation & Failure Reporting Strategy](maintenance/rspec-error-consolidation.md)

## Deployment

Coolify resource and demo-environment guides.

- [Coolify Demo Environment Setup](coolify/demo-environment.md)
- [Coolify Separate Resources Setup](coolify/separate-resources.md)

## Past proposals

Earlier booking-workspace, boat, and notes decisions; historical implementation instructions.

- [Boat Transfer — Enablement Considerations](past-proposals/BOAT_FEATURE_ENABLE_CONSIDERATION.md)
- [Booking Notes — Tech Debt](past-proposals/BOOKING-NOTES-TECH-DEBT.md)
- [Booking Workspace Redesign — PR Phase Checklist](past-proposals/BOOKING_WORKSPACE_CHECKLIST_PR_PHASE.md)
- [Booking Workspace Redesign Proposal](past-proposals/BOOKING_WORKSPACE_PROPOSAL.md)

## Historical snapshots

The [archive index](archive/README.md) covers the generated codebase map, the old
Preline plans, and dated portal UI audits. Current portal rules take precedence over them.

## Operational and asset guides

- [Hotel onboarding guide](../guides/hotel_admin/onboarding.md)
- [Concierge background asset](../app/assets/images/concierge/README.md)
