# Guest Concierge Flow

Status: Decided. This document authorizes implementation.

## State Model

Guest Concierge has three access states:

```text
Public Concierge
No stay identified
        |
        | Guest opens a stay link
        v
Locked Stay Page
Stay identified, device not verified
        |
        | Guest enters the booking confirmation code
        v
Checked-in Concierge
Stay identified, device verified
```

The stable stay URL serves both the locked and authenticated page. The stay session determines which page state the server shows.

## URLs

Example hotel identifiers:

```text
hotel_code       = 10101
public_id        = 550e8400-e29b-41d4-a716-446655440000
stay_access_id   = V8mN2xQp7K
```

Public Concierge:

```text
GET /concierge/10101/550e8400-e29b-41d4-a716-446655440000
```

Checked-in Concierge:

```text
GET /concierge/10101/550e8400-e29b-41d4-a716-446655440000/stay/V8mN2xQp7K
```

Device verification:

```text
POST /concierge/10101/550e8400-e29b-41d4-a716-446655440000/stay/V8mN2xQp7K/verify
```

## Flow 1: Public Concierge

1. The guest opens the hotel QR code or public URL.
2. The server locates the hotel from the hotel code and public UUID.
3. The server shows Public Concierge without guest authentication.
4. The guest can use the public hotel services.

The public page does not identify an active stay.

## Flow 2: Staff Check-in Creates Stay Access

1. Staff completes the booking check-in in the Hotel Portal.
2. The booking status becomes `checked_in`.
3. The server creates the stable stay-access record.
4. The server sends the stay link to the booking email.
5. The guest opens the link and verifies the device.

Pre-check-in does not create stay access. A `confirmed` booking has no stay page.

The stay link contains `stay_access_id`. It does not contain the confirmation code or a session credential.

## Flow 3: Known Device Reopens the Stay Link

1. The guest opens the stable stay link.
2. The browser sends its stay-session cookie.
3. The server finds the stay session.
4. The server validates the hotel, booking, status, expiration, and revocation state.
5. The server shows Checked-in Concierge.

The guest does not enter the confirmation code again while the session remains valid.

## Flow 4: Unknown Device Opens the Stay Link

1. The guest opens the stable stay link on another device.
2. The server finds no valid stay session for that browser.
3. The server shows the locked stay page at the same URL.
4. The guest enters the booking confirmation code and the guest last name.
5. The browser submits the form to the verification route.
6. The server validates the code and the last name against the stay booking.
7. The server creates a new stay session for that browser.
8. The server redirects to the stable stay URL.
9. The server shows Checked-in Concierge.

The first device keeps its session. The second device receives an independent session.

## Flow 5: Incorrect Confirmation Code

1. The guest submits an incorrect confirmation code or last name.
2. The server records the unsuccessful attempt without the raw code.
3. The server applies the applicable delay.
4. The server shows a generic error on the locked stay page.

The response does not reveal whether the stay, guest, or confirmation code exists.

After the fifth incorrect attempt in one hour, the server locks the stay-access record. The locked page then offers email recovery. The server sends a magic link to the booking email.

## Flow 6: Expired or Revoked Access

1. The guest opens the stable stay link.
2. The server finds an expired, revoked, or ineligible stay-access record.
3. The server removes the invalid stay session from the browser.
4. The server shows a neutral unavailable page.

The unavailable page does not reveal booking or guest information.

## Flow 7: Checkout Grace Period

1. Staff completes the booking check-out.
2. The booking status becomes `completed`.
3. The stay session stays valid for 7 days.
4. The guest can still open the stay page for the folio, the invoice, and a refund request.
5. After 7 days, the server shows the unavailable page.

## Request Authorization

Each protected request follows this decision path:

```text
Does the route identify an active stay-access record?
        | no
        v
Show the unavailable page

        | yes
        v
Does the browser have a valid stay session?
        | no
        v
Show the locked stay page

        | yes
        v
Does the session match the route hotel and booking?
        | no
        v
Reject access

        | yes
        v
Is the booking still eligible?
        | no
        v
Revoke the session and show the unavailable page

        | yes
        v
Show Checked-in Concierge
```

## Booking Resolution

The stay page gets its booking from the validated stay session:

```text
current_concierge_stay.booking
```

The stay page does not accept a booking ID from a request parameter. Shared services receive the booking from this trusted scope.

## Session End

The system ends a stay session after:

- 7 days from checkout.
- Booking cancellation.
- Stay-access revocation by staff.
- Another configured terminal booking state.

Revocation ends every session for that stay. The system does not revoke one device.

## Device Example

```text
Phone B opens the stay link first
        |
        v
Phone B enters the confirmation code
        |
        v
Phone B receives stay session B

Phone A opens the same stay link later
        |
        v
Phone A enters the confirmation code
        |
        v
Phone A receives stay session A

Both sessions remain independent and valid
```
