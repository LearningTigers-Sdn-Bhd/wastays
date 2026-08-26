# Phase 8 — Commercial configuration slices

Read `docs/onboarding/handoffs/README.md` first for the shared pattern and rules.

## Goal

Make four sections real so a hotel's commercial and payment setup can be completed without
entering the normal settings portal.

`PLAN.md` §"Phase 8" is the scope authority.

## Deliver as four independently reviewable commits

The catalog already orders them, each depending on the last
(`app/services/onboarding/section_catalog.rb:15-18`):

| Section | Required | Depends on |
|---|---|---|
| `extra_charges` | optional (skippable) | `rates_availability` |
| `discounts` | optional (skippable) | `extra_charges` |
| `payment_methods` | **required** | `discounts` |
| `corporate_accounts` | optional (skippable) | `payment_methods` |

Do not collapse these into one page or one commit.

## Existing code to reuse

| Section | Reuse | Existing controller |
|---|---|---|
| Extra charges | `Financials::EnsureDefaultExtraCharges`, `ExtraCharges::Save` | `app/controllers/hotel_portal/extra_charges_controller.rb` |
| Discounts | `Discounts::EnsureDefaults`, `Discounts::Save` | `app/controllers/hotel_portal/discounts_controller.rb` |
| Payment methods | `PaymentMethods::EnsureDefaults`, `PaymentMethods::Save`, `PaymentMethods::Eligibility` | `app/controllers/hotel_portal/payment_methods_controller.rb` |
| Corporate accounts | `HotelCorporateAccount`, `CorporateInvitations::CreateService` / `ResendService` / `AcceptService` | `app/controllers/hotel_portal/corporate_accounts_controller.rb` |

## The defaults-on-visit problem

All three `EnsureDefaults` services are currently invoked as a **page-visit side effect** in
their settings controllers' index actions. `PLAN.md` explicitly forbids that pattern for
onboarding: "default financial records are initialized deliberately rather than as a side
effect of visiting an index page."

Phase 5 hit the same problem first and settled it: the `Onboarding::*` service calls the
relevant `EnsureDefaults` **inside its own transaction, on a save the owner initiated** —
see `Onboarding::SaveTaxesFees` (`Financials::EnsureDefaultTransactionCodes`) and
`Onboarding::SaveRoomRevenue` (`ReservationPolicies::EnsureDefaults`). Follow that here
rather than inventing a second approach. Do not add `EnsureDefaults` to a `before_action`
in the onboarding controller.

## Cross-section dependencies

These are the constraints from `PLAN.md`; enforce them in the completion contracts:

- Taxes (Phase 5) must be available for extra-charge assignment
- Discounts can only target established eligible charge codes
- Payment surcharges can reference existing extra charges
- **At least one usable payment method is required** — this is why `payment_methods` is the
  only required section of the four
- Dependency invalidation warns instead of silently deleting references

Because extra charges are skippable but discounts and payment surcharges can reference
them, decide what a skipped `extra_charges` means downstream: discounts with no eligible
codes, and payment methods with no surcharge option. Make that explicit in the UI rather
than presenting an empty picker.

## Corporate invitations must be queued

`CorporateInvitations::CreateService` sends immediately. Onboarding must not send during
setup — invitations are queued and delivered only after successful submission (Phase 10),
and they do not block on acceptance.

Phase 4 already established the pattern for this with `onboarding_staff_drafts` +
`Onboarding::SaveTeamSetup`. Mirror it: store requested corporate invitations as drafts,
without delivery.

**`IMPLEMENTATION_MAP.md` §8 item 11 flagged this as unresolved.** It is now decided.

### Resolved: `onboarding_corporate_drafts`

Real columns mirroring `onboarding_staff_drafts`, plus two for delivery:

| Column | Purpose |
|---|---|
| `hotel_id`, `email` | unique on `(hotel_id, LOWER(email))` |
| `company_name`, `account_type`, `relationship_type`, `credit_limit`, `credit_currency`, `payment_terms_days` | what the invitation carries; `CorporateInvitation` keeps these in `metadata` jsonb, but onboarding validates them, so they are columns here |
| `invitation_id` | **the idempotency marker.** Unique where not null |
| `delivered_at` | when submission sent it |

**Phase 10 delivers `hotel.onboarding_corporate_drafts.undelivered`,** setting `invitation_id`
and `delivered_at` in the same transaction that creates the invitation. A retried submission
sees `invitation_id` present and skips, and the partial unique index makes double-linking
impossible even under a race.

Two consequences Phase 10 must honour:

- **Drafts are never deleted after delivery.** They are the idempotency record.
  `SaveCorporateDrafts` upserts rather than `delete_all`-ing (unlike `SaveTeamSetup`), and
  refuses to remove a delivered row, so a changes-requested re-edit cannot cause a resend.
  `onboarding_staff_drafts` has the same latent problem and no marker — Phase 10 needs to
  solve it there too.
- **Validation happens at draft time.** `OnboardingCorporateDraft` mirrors
  `CorporateInvitation`'s rules and calls `CorporateInvitations::CheckEligibility` (extracted
  from `CreateService` in this phase) so a draft that saves will not be rejected at send time.
  It also rejects an email colliding with a pending invitation or a staff draft: the
  `invitations` unique index on `(hotel_id, email) WHERE accepted_at IS NULL` is **not** scoped
  by kind, so that collision would otherwise explode during delivery.

## Explicit skip decisions

Extra charges, discounts, and corporate accounts support skipping, but `UpdateSection`
requires the skip to be a recorded decision with an audit event — not silent omission.
`Onboarding::Readiness` blocks submission when an optional section is neither resolved nor
skipped, so the UI must make the skip an affirmative choice (see
`Onboarding::SaveTeamSetup` for the Phase 4 precedent).

## Do not

- Send any invitation during setup
- Initialize defaults on page render
- Delete records that other sections reference — invalidate and warn instead
- Break the existing settings-portal controllers for these four areas

## Tests

- Service specs per section: save, completion contract, explicit skip, invalidation
- Request specs: prerequisite locking across the four-section chain, skip semantics,
  the required-ness of `payment_methods`
- Regression coverage that the existing settings pages still work through the same
  reused services
- System spec: owner configures a payment method and skips the optional three

```bash
bin/test financials
```

```bash
bin/test hotel_management
```

## Done when

All four sections reach a resolved state (complete or explicitly skipped) with no
`placeholder` metadata, at least one usable payment method is enforced, and corporate
invitations are stored as queued drafts that nothing has sent.
