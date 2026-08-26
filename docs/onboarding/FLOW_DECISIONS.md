# Hotel Onboarding Flow Decisions

## Status

Agreed product decisions for the integrated admin-created hotel onboarding flow.

This document defines the intended product behaviour. It does not describe the current implementation.

## Objective

Separate account provisioning from operational hotel setup:

- An admin creates the account and chooses platform-level commercial settings.
- The hotel owner completes operational setup in a dedicated onboarding experience.
- An admin reviews the completed setup before the hotel becomes live.
- Staff do not enter the application until setup has been submitted.

## Hotel lifecycle

Use four hotel lifecycle states:

```text
setup -> pending_review -> live -> suspended
```

| Status | Meaning |
|---|---|
| `setup` | The hotel exists, but operational onboarding is incomplete. |
| `pending_review` | The owner submitted onboarding and the hotel is awaiting admin review. |
| `live` | The hotel was approved and normal operations and booking eligibility are enabled. |
| `suspended` | Hotel access and booking eligibility are disabled. |

Onboarding page progress is not encoded in the hotel status. Each onboarding section separately records one of:

- Not started
- In progress
- Complete
- Skipped
- Needs attention

User activation and email verification belong to the user or invitation lifecycle, not the hotel lifecycle. `approved` and `live` must not remain separate operational concepts.

## Admin hotel creation

The admin is responsible for:

- Company or group account details
- Owner name and email
- Hotel name
- Sell mode
- Subscription plan
- Preferred channel manager or an undecided selection
- Internal salesperson or ownership information when applicable

The admin does not complete the hotel profile, operational setup, rooms, rates, or financial configuration during account creation.

### Sell mode

The admin chooses one permanent sell mode:

- Per room
- Per pax

The owner can see the selected mode during onboarding but cannot change it. Every rate plan inherits the hotel's sell mode.

### Creation actions

| Action | Result |
|---|---|
| Cancel | Discard and return to the previous admin page. |
| Create only | Create the hotel in `setup` without starting owner onboarding. |
| Create & onboard | Create the hotel in `setup`, start onboarding, and send the owner a secure activation invitation. |

`Create & onboard` does not authenticate the admin as the owner. It leads the admin to an onboarding handoff or tracker page.

The owner must receive a secure activation/password-creation link. A shared default password is not part of the target flow.

## Owner access and routing

After activation and login, an owner whose hotel is in `setup` resumes at the current onboarding page.

Recommended route shape:

```text
/hotel/:hotel_slug/onboarding
```

The root onboarding route resolves to the current resume page.

While the hotel is in `setup`, normal hotel portal pages redirect the owner to onboarding. The following remain available:

- Onboarding routes and supporting form/upload endpoints
- Personal profile and password/security
- Help and support
- Logout
- Invitation activation

The redirect must not apply indiscriminately to every request because that would create loops and break required endpoints.

Owners may revisit completed earlier steps. Future steps are available only after their prerequisites are satisfied. Opening a locked future URL returns the owner to the earliest incomplete prerequisite with an explanation.

## Onboarding sequence

### Phase 1: Property

#### 1. Property profile — required

Collect:

- Property and legal identity
- Address, city, country, and timezone
- Contact information
- Default currency
- Star rating
- Amenities
- Photos and featured photo
- Relevant property information and policies

### Phase 2: Team

#### 2. Team Management — required

One page holds both halves of the Team phase. It was two steps until 2026-08-26;
the roles half had a read-only list and a checkbox, which is not a step's worth
of work.

The top of the page shows the four seeded presets as cards, each with a one-line
summary of the job it is for:

- Hotel Owner
- General Manager
- Front Desk
- Housekeeper

Presets are read-only during onboarding. Saving the page records a fingerprint of
their permissions, and `Onboarding::Readiness` blocks submission when the
permissions move after that. Editing and custom role management remain
plan-gated settings features after launch.

The lower half is the draft staff table. The owner enters email addresses and
assigns preset roles. These records stay drafts throughout setup, and invitations
are sent only after onboarding is successfully submitted. Invitation acceptance
does not block admin review or launch.

Continuing with an empty table records `no_additional_staff` and completes the
step. The step is required, so it cannot be skipped: the roles still need
confirming even when nobody else needs access.

### Phase 3: Finance

#### 3. Taxes and fees — required confirmation

Configure system and custom taxes and fees, including:

- SST
- Tourism tax
- Custom taxes and mandatory fees
- Percentage or fixed amount
- Enabled state
- Foreign-guest applicability

#### 4. Room revenue — required

Configure:

- Room revenue transaction configuration
- Taxes assigned to room revenue
- Posting behaviour
- Relevant reservation policies

Taxes precede room revenue so they are available for assignment. Room revenue precedes rooms and rate setup so the financial treatment of a room sale is already defined.

### Phase 4: Rooms and rates

#### 5. Rooms — required

Configure:

- Room categories or types
- Quantity
- Maximum adults, children, and total occupancy
- Room numbers when required by the room-number mode
- Amenities and smoking/pet policies

At least one valid room type with positive quantity is required.
Descriptions, photos, room groups, and pricing are not collected on this onboarding page.
Phase 7 owns pricing; optional descriptive room details remain available in regular Settings.

#### 6. Rate plans and availability — required

Configure:

- Standard and additional rate plans
- Pricing appropriate to the hotel's sell mode
- Child pricing where applicable
- Rates for actual dates
- Open inventory and available quantities
- Initial one-year coverage

A rate-plan definition alone is not sufficient for launch. The hotel must have sellable rates and inventory.

##### Per-room pricing

Per-room pricing captures a room rate with occupancy supplements, such as:

- Default room rate
- Base occupancy
- Extra-adult charge
- Extra-child charge
- Maximum occupancy

##### Per-pax pricing

Per-pax pricing captures an adult occupancy price for each supported occupancy.

The pricing grid uses the highest room occupancy as its maximum set of columns. A room enables only the cells up to its own supported adult occupancy. Higher occupancy cells display `Not available` or `—`, are not editable, are not saved, and are not validated.

If maximum occupancy increases, newly supported prices become required. If it decreases, the owner is warned before now-invalid higher-occupancy prices are removed.

##### Child age bands

For per-pax hotels, child age bands are configured once per rate plan and apply to every room type using that rate plan.

A rate plan owns:

- Child age ranges
- Infant and child pricing rules
- Fixed or percentage pricing
- How children contribute to the booking total

A room type owns:

- Maximum adults
- Maximum children
- Maximum total occupancy

Different rate plans may use different child pricing. New rate plans may be prefilled from a hotel-level default child-band template to avoid repeated entry.

##### One-year initial population

The owner defines bulk rules rather than editing 365 individual dates:

- Start date
- End date defaulting to one year
- Weekday and weekend pricing
- Available quantity
- Applicable room types and rate plans
- Closed dates and exceptions

The product must also provide expiry warnings, coverage indicators, and bulk extension. A rolling future horizon is preferable so initial setup does not silently expire after one year.

### Phase 5: Commercial

#### 7. Extra charges — optional

Configure charge name, code, pricing method, amount, charging unit, override behaviour, active state, and applicable taxes. The owner may choose `No extra charges for now`.

#### 8. Discounts — optional

Configure discount name, code, fixed or percentage pricing, application scope, applicable room revenue or extra charges, override behaviour, and active state.

Discounts follow extra charges because they may target the charge codes established by room revenue and extra charges. The owner may choose `No discounts for now`.

#### 9. Payment methods — required

Configure cash, card, bank transfer, payment gateways, advance/deposit support, default cash behaviour, and payment surcharges.

Payment methods follow extra charges because a surcharge may reference an extra-charge configuration. At least one active usable payment method is required.

#### 10. Corporate accounts — optional

The owner may prepare corporate account invitations and initial credit terms or explicitly choose `Configure later`.

External acceptance does not block onboarding or launch. Any invitation requested during onboarding is queued until submission.

#### 11. Channel manager — optional

Rescoped during delivery to credential intake, because that is how the client already works: they collect OTA extranet logins on a spreadsheet and connect the channels themselves afterwards.

The owner hands over the logins their channels need — channel, property ID, username, password, and market manager contact — and nothing is connected or sent from this page. Usernames and passwords are encrypted at rest and are write-only from the portal: never rendered back into a field, and redacted from a failed submission. Only the WAStays team reads them, which the page says on the page where they are typed.

The owner's two answers are therefore "here are my logins" and "none for now". Continuing from an empty table is the second answer.

The admin's preferred provider is displayed and never written here, so an owner who hands over nothing still keeps the provider choice made at creation.

Connection itself — provisioning, room and rate-plan mapping, the initial rate and availability push, retry, and diagnostics — is deferred superadmin work, and provisioning still occurs only after rooms, rate plans, rates, and inventory are ready. Until that lands, no UI reads the stored rows.

The higher-level product decision about whether a channel manager will eventually become mandatory remains open.

### Phase 6: Review

#### 12. Review and submit — required

The readiness review shows required completion, explicit optional decisions, warnings, and blocking issues.

Required launch-readiness checks include:

- Property profile complete
- Roles confirmed
- Staff decision confirmed
- Taxes confirmed
- Room revenue configured
- At least one valid room type
- Valid sell-mode pricing
- One year of initial rate and inventory coverage
- At least one active usable payment method

Optional sections must be configured or answered. Continuing from an empty table
is that answer — it records the same decision an explicit skip once did.

On successful submission:

1. Lock and revalidate the current setup.
2. Create the immutable submission snapshot and durable delivery effects.
3. Change the hotel to `pending_review` and record the audit event in the same transaction.
4. Make onboarding read-only until changes are requested.
5. After commit, process queued staff/corporate invitations and notify the assigned
   salesperson plus superadmins. Delivery failures remain retryable and do not undo the
   submission.

## Admin review

The admin can:

### Request changes

- Return the hotel to `setup`.
- Select affected onboarding sections.
- Add an explanation.
- Mark those sections `Needs attention`.
- Notify the owner and resume them at the affected section.
- Keep the earlier submission as immutable history; do not delete or resend invitations.

### Approve & go live

- Run final server-side readiness validation.
- Compare the current configuration digest with the submitted snapshot and block approval
  if the property changed after submission.
- Change the hotel to `live`.
- Enable normal hotel portal access.
- Enable booking eligibility and normal scheduled operations.
- Retain the approved snapshot as the read-only onboarding summary.

Training sessions remain visible and manageable in admin review but are informational and
never block submission or launch. OTA review shows channel names and credential presence
only, never usernames or passwords.

### Suspend

After launch, suspension changes the hotel to `suspended` and applies the platform's access and booking restrictions.

## Dependency invalidation

Earlier steps remain editable during setup, but changes may invalidate later steps.

Examples:

- Tax changes may invalidate room revenue and extra-charge tax assignments.
- Room capacity changes may invalidate per-pax pricing and channel mappings.
- Removing a room may invalidate rate plans, availability, and channel mappings.
- Removing an extra charge may invalidate discounts or payment surcharges that reference it.

The system must warn before destructive changes and mark affected downstream steps `Needs attention`. It must not silently discard valid downstream configuration.
