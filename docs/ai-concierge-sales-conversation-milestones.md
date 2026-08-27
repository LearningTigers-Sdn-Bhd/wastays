# AI Concierge Sales Conversation Milestones

Status: In progress
Started: 2026-08-27
Last updated: 2026-08-27

## Progress

| Milestone | Status |
|---|---|
| Milestone 0 — Conversation contract | Approved |
| Milestone 1 — Next-action policy | Completed |
| Milestone 2 — Hotel-information replies | Completed |
| Milestone 3 — Price exploration | Completed |
| Milestone 4 — Existing-booking conversations | Not started |
| Milestone 5 — WhatsApp welcome | Not started |
| Milestone 6 — Protection and release | Not started |

## Purpose

This plan changes the AI Concierge from a direct information bot into a helpful hotel sales concierge.

The concierge must answer the guest first. It must then offer a useful next action that matches the guest's journey.

The concierge must remain accurate. Ruby continues to control policies, dates, prices, availability, room names, rate plans, and quotation links.

## Target experience

Each reply follows this pattern:

1. Acknowledge the guest when an acknowledgment adds value.
2. Answer the question clearly.
3. Present a benefit, alternative, or useful detail.
4. Offer one relevant next action.
5. Return to an interrupted booking when applicable.

The next action must fit the guest's situation. The concierge must not repeat “Would you like to book?” after every answer.

### Examples

#### Check-in time

> Check-in starts at 5:00 PM. Would you like me to find a room for your travel dates?

#### Pet policy

> We are sorry, but the hotel does not allow pets. If this policy works for you, I can help you find a suitable room.

#### Amenity

> Yes, complimentary Wi-Fi is available throughout the hotel. Are there other facilities that are important for your stay?

#### Nearby attractions

> The Waterfront and Main Bazaar are near the hotel. Would you like directions or room information for your travel dates?

#### Cheapest price

> I can help you find our lowest available rate. What dates are you considering?

#### Existing booking

> Hello, and welcome to {hotel_name}. We found your stay from {check_in} to {check_out}. How can we help with your booking?

## Product rules

- Answer the guest before giving a sales prompt.
- Use one relevant next action per reply.
- Do not hide restrictions, prices, or unavailable services.
- Do not pressure the guest after a refusal.
- Do not treat a price inquiry as consent to book.
- Do not offer a new booking when the guest asks about an existing booking.
- Do not invent a hotel benefit, discount, policy, room, rate, or attraction.
- Preserve the active booking when the guest asks an information question.
- Resume the active booking only after the information question is resolved.
- Keep human-support behavior available when the system cannot give a safe answer.

## Conversation coverage

The plan uses eight guest intentions and five guest stages. This gives 40 primary conversation contexts.

### Guest intentions

1. Hotel information.
2. Amenities and services.
3. Policies and restrictions.
4. Room information.
5. Nearby attractions.
6. Prices and rates.
7. Availability and new bookings.
8. Existing bookings.

### Guest stages

1. Browsing.
2. Considering a stay.
3. Making a booking.
4. Holding a confirmed booking.
5. Staying at the hotel.

Not every context needs unique copy. The implementation uses shared response rules and tested next-action types.

## Current system boundaries

The current Concierge already separates information questions from booking activity.

Application services create the answer before the reply stylist changes its tone. The rewrite verifier protects numbers, currencies, links, and names.

Hotel-knowledge replies currently bypass the reply stylist. The hotel-knowledge composer creates their final wording.

Price questions use the booking path because a valid price depends on dates. This path must support price exploration without claiming booking consent.

Proactive WhatsApp messages use the notification and Relay path. They do not use the reactive AI Concierge response path.

## Milestone 0 — Approve the conversation contract

Status: Approved

This milestone defines the product behavior. It changes no application behavior.

### Work

- Approve the eight guest intentions.
- Approve the five guest stages.
- Approve the allowed next-action types.
- Approve positive, restrictive, unavailable, and missing-information examples.
- Decide which replies need no sales question.
- Decide how often the Concierge can repeat a sales prompt.
- Decide whether the confirmed-booking welcome sends immediately or at a scheduled time.

### Exit criteria

- Product owners approve the conversation matrix.
- Product owners approve the example replies.
- Product owners approve the price-exploration boundary.
- Product owners approve the WhatsApp welcome timing.

## Milestone 1 — Add the next-action policy

Status: Completed on 2026-08-27

This milestone adds one deterministic policy for the next useful action.

The policy reads application state. It does not ask the language model to decide business facts.

### Inputs

- Guest intention.
- Answer outcome.
- Current booking task.
- Resumable suspended-booking status.
- Human-support requirement.
- Sales-offer suppression flag.

### Outputs

- `offer_booking_help`.
- `offer_price_search`.
- `resume_booking`.
- `continue_booking`.
- `offer_alternative_search`.
- `offer_front_desk`.
- `none`.

### Delivered

- Added one validated `NextAction` value.
- Added one deterministic next-action policy.
- Added `next_action` to the internal `DomainResponse` contract.
- Attached policy results to hotel-information and booking responses.
- Kept `next_action` out of the public API response.
- Kept existing guest-facing reply text unchanged during this milestone.

### Exit criteria

- [x] One service owns next-action selection.
- [x] Unit tests cover every output.
- [x] An information question does not erase a booking task.
- [x] Human support overrides commercial actions.
- [x] The public API does not expose `next_action`.

## Milestone 2 — Improve hotel-information replies

Status: Completed on 2026-08-27

This milestone applies the next-action policy to reactive information replies.

### Covered replies

- Hotel information.
- Amenities and services.
- Policies and restrictions.
- Nearby attractions.
- Room information.
- Clarification questions.
- Missing hotel information.

### Rules

- Keep the hotel fact unchanged.
- Add the next action after the fact.
- Use a relevant action instead of a generic closing sentence.
- Give an alternative when a policy or unavailable service blocks the guest's request.
- Return to the suspended booking after the information answer.

### Delivered

- Added deterministic copy for every next-action kind.
- Added the selected action after the factual hotel answer.
- Added contextual copy for policies, room information, general information, and booking resumption.
- Kept clarification replies free of additional sales prompts.
- Added one front-desk action when hotel information is missing.
- Added internal sales-offer state without a database migration.
- Added English, Malay, and Chinese refusal recognition.
- Kept the chat active after a sales refusal.
- Suppressed one optional offer after a refusal.
- Kept booking questions and front-desk guidance visible during suppression.
- Kept `next_action` and `sales_task` out of public API responses.

### Exit criteria

- [x] Each covered reply has an intentional next action or an intentional stop.
- [x] Restrictions remain clear and accurate.
- [x] Missing information does not become an invented sales claim.
- [x] Booking interruption and resumption specs pass.
- [x] Hotel-knowledge reply specs pass.
- [x] Refusal and one-off suppression specs pass.
- [x] Public Concierge request specs pass.

### Validation

- Full AI Concierge domain: 648 examples, 0 failures.
- AI Concierge API requests: 42 examples, 0 failures.
- Public Concierge chat requests: 43 examples, 0 failures.
- Turn and booking boundaries: 90 examples, 0 failures.
- Service coverage: 3 examples, 0 failures.
- RuboCop: 21 files, no offenses.

Repository policy prohibits browser testing. Request specs cover the public Concierge chat path.

## Milestone 3 — Separate price exploration from booking commitment

Status: Completed on 2026-08-27

This milestone improves commercial questions without changing price authority.

The booking search remains the source of prices and availability. The conversation wording distinguishes search from commitment.

### Price-exploration flow

1. Ask for missing dates and party details.
2. Search the application-controlled inventory.
3. Show the lowest valid option as a starting price.
4. Offer room details or booking continuation.
5. Create a quotation link only after the existing confirmation flow.

### Required distinctions

- “Find a price” is not “make a booking.”
- “Show the cheapest option” is not “select this option.”
- “Continue with booking” is not “confirm the quotation.”
- “Confirm the quotation” is not “complete payment.”

### Delivered

- Added a persisted booking purpose for price exploration and booking commitment.
- Kept the journey purpose through search-detail collection, information interruptions, and booking resume.
- Added a priced shortlist that marks the lowest starting option.
- Kept flexible-date summaries accurate without presenting one result as the full search range.
- Made a bare option number show room facts and all returned rate plans during price exploration.
- Added explicit price-option continuation before room or rate-plan selection.
- Kept declined options available for more exploration without another sales prompt.
- Added deterministic acceptance of a saved price-search offer.
- Kept `action_name` empty until the guest explicitly continues with booking.
- Kept quotation creation behind the existing quotation-confirmation question.
- Added the exploration state without a database migration or a new public API field.

### Exit criteria

- [x] A price inquiry can collect search details without claiming booking consent.
- [x] The displayed lowest price comes from returned rate plans.
- [x] The reply includes the searched dates and guest details.
- [x] The guest can request room details before continuing.
- [x] The existing quotation confirmation remains required.
- [x] Booking and rate-plan specs pass.

### Validation

- Full AI Concierge domain: 666 examples, 0 failures.
- Booking search, availability, effective-rate, and quotation services: 85 examples, 0 failures.
- Service coverage: 3 examples, 0 failures.
- RuboCop: 22 files, no offenses.

Repository policy prohibits browser testing. Request specs cover the public Concierge API flow.

## Milestone 4 — Improve existing-booking conversations

Status: Not started

This milestone gives confirmed guests a service-focused conversation.

### Reactive welcome

When a confirmed guest writes, the Concierge can acknowledge the known stay.

The reply can offer:

- Check-in information.
- Parking information.
- Directions.
- Hotel facilities.
- Special-request guidance.
- Front-desk assistance.

The reply must not invite the guest to make the same booking again.

### Exit criteria

- The Concierge uses only bookings matched to the guest and hotel.
- The reply names the correct stay dates.
- The reply does not expose another guest's booking.
- Multiple active bookings produce a clear choice.
- No active booking produces a safe response.
- Booking-context specs pass.

## Milestone 5 — Add the proactive WhatsApp welcome

Status: Not started

This milestone sends a welcome inquiry through the existing notification and Relay path.

WAStays does not connect to WhatsApp directly. The Relay receives a WAStays webhook and sends the WhatsApp message.

### Proposed message

> Hello, and welcome to {hotel_name}. Thank you for booking with us for {check_in}. Do you have questions about your stay?

### Delivery rules

- Send only for an eligible confirmed booking.
- Include the hotel name and correct stay dates.
- Use the hotel's WhatsApp number and the guest's phone number.
- Give each welcome delivery a stable idempotency key.
- Do not send duplicate welcome messages after retries.
- Do not send for a cancelled booking.
- Update or replace pending content after a relevant booking change.
- Record delivery status and errors.
- Obey the template and delivery requirements defined by the WhatsApp owner.

The current pre-arrival scheduler creates messages two days and one day before arrival. Product approval determines whether this welcome is immediate or scheduled.

### Exit criteria

- One eligible booking creates one welcome delivery.
- Relay retries do not create duplicate guest messages.
- Booking updates do not send stale dates.
- Booking cancellations stop pending delivery.
- Training hotels do not send the message.
- Notification, job, webhook, and payload specs pass.
- The Relay contract documents the new event.

## Milestone 6 — Protect, evaluate, and release

Status: Not started

This milestone proves that the new conversation behavior is safe and useful.

### Rewrite protection

The final reply must preserve:

- Prices.
- Dates.
- Times.
- Currencies.
- Links.
- Room names.
- Rate-plan names.
- Required next-action meaning.

The deterministic template remains the fallback when the stylist fails or returns an unsafe rewrite.

### Acceptance matrix

Test the 40 primary contexts. Add variants for these outcomes:

- A positive answer.
- A restriction.
- Missing hotel information.
- No availability.
- A price question without booking consent.
- A suspended booking.
- An existing booking.
- Multiple existing bookings.
- A human-support request.
- English and Malay replies.
- Business and cheerful tones.

### Product measurements

Measure these conversation events:

- The guest provides dates after an information reply.
- The guest requests a price search.
- The guest selects a room.
- The guest reaches a quotation link.
- The guest requests human support.
- The guest stops after repeated sales prompts.

### Exit criteria

- Focused AI Concierge specs pass.
- Notification and Relay specs pass.
- The relevant test domains pass.
- Reviewed transcripts contain no false facts.
- Reviewed transcripts contain no inappropriate booking prompts.
- The release has a safe rollback path.

## Recommended delivery order

1. Milestone 0 is approved.
2. Milestones 1 and 2 are completed.
3. Complete Milestone 3 after transcript review.
4. Complete Milestone 4 after booking-context review.
5. Complete Milestone 5 as a separate notification change.
6. Complete Milestone 6 before general release.

Milestones 1 to 4 form the reactive Concierge change. Milestone 5 is separate because it sends a proactive external message.

## Main implementation areas

### Reactive Concierge

- `app/services/ai_concierge/orchestration/core/intents.rb`
- `app/services/ai_concierge/orchestration/hotel_knowledge/reply_composer.rb`
- `app/services/ai_concierge/message_builders/booking_actions_builder.rb`
- `app/services/ai_concierge/orchestration/turn/booking_context_handler.rb`
- `app/services/ai_concierge/orchestration/turn/response_persister.rb`
- `app/services/ai_concierge/agents/reply_stylist.rb`
- `app/services/ai_concierge/agents/rewrite_verifier.rb`
- `app/services/ai_concierge/state/conversation_task_manager.rb`

### Proactive WhatsApp delivery

- `app/services/notifications/dispatcher.rb`
- `app/services/notifications/pre_arrival_scheduler.rb`
- `app/services/notifications/channels/whatsapp_webhook.rb`
- `app/services/notifications/payload_builders/`
- `app/models/notification_config.rb`
- `app/models/notification_delivery.rb`
- `docs/whatsapp-relay-contract.md`

## Out of scope

- The language model setting prices or availability.
- The language model creating a payable quotation directly.
- Automatic discounts that the hotel did not configure.
- Automatic upsells that have no application-controlled inventory.
- Changes to payment processing.
- Direct WhatsApp credentials inside WAStays.
- A replacement for human support.

## Completion definition

This project is complete when reactive and proactive replies use the approved guest-stage rules.

The replies must remain factual, helpful, and commercially useful. They must preserve booking state and respect the guest's choices.
