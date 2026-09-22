# Guest Concierge Requirements

Status: Decided. This document authorizes implementation.

## Purpose

Guest Concierge provides two guest experiences for one hotel:

- Public Concierge gives anonymous access to public hotel services.
- Checked-in Concierge gives authenticated access to one active stay.

Checked-in Concierge is a stay-focused subset of the Guest Portal. It uses a separate access boundary and stay-specific navigation.

## Terms

### Public Concierge

Public Concierge is the anonymous hotel page. A guest can open it from the hotel QR code or public URL.

### Checked-in Concierge

Checked-in Concierge is the authenticated page for one booking. This document also calls it the stay page.

### Stay link

The stay link is a stable URL for one stay. The link identifies the stay-access record but does not authenticate a device.

### Stay session

A stay session authorizes one browser for one booking. More than one browser can hold a valid session for the same stay.

### Guest Portal

The Guest Portal is the account-level product. It can show multiple bookings, hotels, historical stays, invoices, and refunds.

## Product Boundaries

### Public Concierge

Public Concierge must:

- Remain available without guest authentication.
- Remain scoped to one hotel.
- Keep public actions separate from authenticated stay actions.
- Provide the entry point for pre-check-in.
- Show the public service hub before a stay session exists.

### Checked-in Concierge

Checked-in Concierge must:

- Represent exactly one booking and one hotel.
- Use the same visual language as Public Concierge.
- Use a dedicated route and stay session.
- Get the booking from the stay session.
- Permit access from multiple verified devices.
- End access after the authorized stay ends or staff revokes access.

Checked-in Concierge must not:

- Use the Guest Portal session as its authorization boundary.
- Show other bookings from the same guest account.
- Show stays from another hotel.
- Accept a booking ID or confirmation code in the URL.
- Treat the hotel public UUID or stay link as authentication.

### Guest Portal

The Guest Portal remains a separate account-level product. Checked-in Concierge can reuse its services, presenters, and interface components.

The stay page must not redirect the guest into the Guest Portal. The guest does not need a Guest Portal session.

## URL Structure

The routes use these forms:

| Page | Route |
| --- | --- |
| Public Concierge | `/concierge/:hotel_code/:public_id` |
| Checked-in Concierge | `/concierge/:hotel_code/:public_id/stay/:stay_access_id` |
| Device verification | `POST /concierge/:hotel_code/:public_id/stay/:stay_access_id/verify` |
| Guest Portal login | `/guest/login` |
| Guest Portal booking | `/guest/bookings/:booking_id` |

`stay_access_id` must be random and non-sequential. It must not contain a database ID, confirmation code, email address, or phone number.

## Access Requirements

### Stable stay link

The stay link must remain reusable during the allowed stay period. A guest can open the same link on more than one device.

The system must not depend on email, WhatsApp, SMS, or an API to authenticate a device through the link alone.

### Unknown device

An unknown device must show a locked stay page. The page must request the booking confirmation code.

The locked page can show the hotel hero and the hotel name. The hotel is already public through the QR code.

The locked page must not show:

- The guest name.
- The room number.
- The stay dates.
- The booking status.
- Financial information.
- Personal information.

### Verified device

After successful verification, the server must create a stay session for that browser. The server must redirect to the same stable stay URL.

The browser must then open the stay page without another challenge while its stay session remains valid.

### Multiple devices

Verification on one device must not invalidate another valid device. Each device must receive an independent stay session.

### Session storage

The browser cookie must use `HttpOnly`, `Secure`, and `SameSite=Lax`. The URL must not contain the session credential.

The server must validate the stay session for each protected request. The server must get the booking from that session.

## Stay Eligibility

The system can create or retain access only for an eligible booking. These booking statuses are eligible:

| Status | Access |
| --- | --- |
| `checked_in` | Full |
| `due_out_detected` | Full |
| `checkout_required` | Full |
| `completed` | Grace period only |

The first three statuses are `Booking::IN_HOUSE_STATUSES`. The implementation must reference that constant.

A `confirmed` booking does not get stay access. Pre-check-in stays a public form. Pre-check-in does not create stay access.

Staff check-in is the only entry point. After check-in, the server sends the stay link by email. The implementation must reuse the existing magic-link mailer.

The design must not require an in-person recovery conversation for normal device changes.

## Security Requirements

The verification flow must:

- Permit 5 attempts per stay each hour.
- Lock the stay-access record after the fifth incorrect attempt.
- Increase the delay after repeated incorrect attempts.
- Offer email recovery after a lock. The server sends a magic link to the booking email.
- Return one generic error for an incorrect code or unavailable stay.
- Record security events without the raw confirmation code.
- Prevent the confirmation code from entering analytics, logs, or chat history.
- Prevent open redirects after successful verification.

The stay session must:

- Belong to one hotel and one booking.
- Expire 7 days after checkout.
- Support explicit revocation of the stay-access record.
- End after cancellation or another terminal booking state.
- Reject requests when the hotel route does not match the session.

Revocation applies to the stay-access record. Revocation ends every session for that stay. The system does not revoke one device.

## Presentation Requirements

Public Concierge and Checked-in Concierge must share their visual system. The stay page must feel like an authenticated state of Concierge.

Shared presentation can include:

- The hotel hero and identity.
- The typography and color system.
- The tile and action patterns.
- The responsive page shell.
- The contact and chat experience.

The stay page navigation must remain focused on the current stay. It must not copy the account-wide Guest Portal navigation.

## Feature Scope

The stay page shows these features in the first delivery:

- The stay summary with the room, the dates, and the status.
- The folio and the invoice.
- The e-invoice.
- The refund request.
- The check-out request.
- The guest request.
- The chat.

The stay page owns the guest financial pages. A guest does not need a Guest Portal session to see an invoice or to send a refund request.

A refund request is a request, not a payment. The guest submits the form. The server creates a `pending` record through `Refunds::SubmitRequest`. Staff approves or rejects the request in the Hotel Portal. No money leaves the account from the stay page.

## Stay Access Records

Each booking gets one stay-access record. Each record gets one `stay_access_id`.

The `stay_access_id` never rotates. To end a link, revoke the record and create a new one.

Every guest on one booking shares one link and one confirmation code. Each device still gets an independent stay session.

A group booking gets one link for each booking in the group. The system does not provide a group link.

A verified stay session satisfies the recommendation unlock. The guest enters the confirmation code one time.

## Reuse Requirements

Implementation must reuse existing booking services before it adds new business logic. Shared services must keep their existing authorization contracts.

Checked-in Concierge can reuse:

- Booking presenters.
- Invoice and document services.
- Stay-control services.
- Request services.
- PanelsUI components.

The checked-in controller must apply the stay-session scope before it calls a shared service.

## Decisions

| Question | Decision |
| --- | --- |
| Eligible booking statuses | `checked_in`, `due_out_detected`, `checkout_required`, and `completed` during the grace period |
| Entry point | Staff check-in only |
| Stay-link delivery | Email, through the existing magic-link mailer |
| Second identity field | No. The schema holds one full name, not a surname. The confirmation code is the only field |
| Session lifetime | Checkout plus 7 days |
| Recovery after a lock | Email magic link |
| `stay_access_id` rotation | Never. Revoke the record and create a new one |
| Guest Portal role | The stay page owns the guest financial pages |
| Group bookings | One link for each booking |
| Revocation | Per stay-access record, not per device |

## Non-Goals

This requirements package does not:

- Define the final page design.
- Replace the Guest Portal.
- Define database tables or migration details.
- Define a group stay page. Each booking gets its own link.
