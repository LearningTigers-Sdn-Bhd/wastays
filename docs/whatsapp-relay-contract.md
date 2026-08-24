# The WhatsApp relay contract

**Who this is for:** whoever builds or maintains the service sitting between
WAStays and WhatsApp. You do not need to read the WAStays codebase.

---

## Why a relay exists at all

WAStays has no WhatsApp connection. No credentials, no client library, nothing.
It has never had one. Every WhatsApp message the product has ever "sent" was a
webhook to an outside service that owns the WhatsApp Business account and does
the actual sending.

```
Guest  ──▶  WhatsApp  ──▶  relay  ──▶  WAStays API
Guest  ◀──  WhatsApp  ◀──  relay  ◀──  WAStays webhook
```

The relay is the only thing in that picture holding WhatsApp credentials. It has
two jobs, and they are independent:

| Direction | What the relay does |
| --- | --- |
| **Inbound** — guest writes | POST the message to the WAStays API, send back whatever it replies |
| **Outbound** — WAStays writes | Receive a webhook, send that text on WhatsApp |

Either half can be built without the other. A relay that only does inbound is
the product as it shipped before August 2026.

---

## Part 1 — Inbound: a guest writes

### Where to send it

```
POST https://<your-wastays-host>/api/v1/hotels/:hotel/ai_concierge/inquiries
Authorization: Bearer <api key>
Content-Type: application/json
```

`:hotel` accepts the hotel's 5-character unique id, its slug, or its numeric id.
Prefer the unique id — it is immutable, the others are not.

The API key is issued per hotel (or per account, covering several hotels). A key
may only address hotels it covers; anything else returns `403`.

### Body

```json
{
  "message": "Do you have a room for this weekend?",
  "phone": "+60123456789"
}
```

`message` and `phone` are both required. Phone may be in any common format —
WAStays canonicalises it and uses it to recognise a returning guest.

A nested form is also accepted, if it is easier for your tooling:

```json
{ "inquiry": { "message": "...", "phone": "..." } }
```

### What comes back

```json
{
  "reply_message": "We have two room types available…",
  "needs_human_support": false,
  "action_name": null,
  "prospect_public_id": "a1b2c3d4"
}
```

Send `reply_message` to the guest. That is the normal case.

### ⚠️ The one case that will break a naive relay

**`reply_message` can be `null`.**

```json
{
  "reply_message": null,
  "needs_human_support": true,
  "action_name": null,
  "prospect_public_id": "a1b2c3d4"
}
```

This means *a human at the hotel has taken over this conversation.* The
assistant is deliberately silent so the guest does not get two answers to one
question — one from the bot and one from the front desk.

```
if reply_message is null  ──▶  send nothing. Stop. This is success.
```

A relay that forwards `reply_message` unchecked will post an empty message to
the guest every time they write while staff are handling them.

The guest's message is still recorded and still reaches the hotel's inbox. The
staff reply arrives later, through Part 2.

### Other responses

| Status | Meaning | What to do |
| --- | --- | --- |
| `200` | Handled. Send `reply_message` unless it is null. | — |
| `401` | Bad or missing API key | Fix config. Do not retry. |
| `403` | Key does not cover that hotel | Fix config. Do not retry. |
| `404` | Unknown prospect | Do not retry. |
| `409` | Two messages raced on one conversation | Retry once, after a short pause. |
| `422` | Blank message, message over 2000 chars, or AI not enabled for the hotel | Do not retry. |
| `500` | Temporary | Retry with backoff. |

Long messages are rejected, not truncated. Split or trim before sending.

---

## Part 2 — Outbound: WAStays writes

### Registering your URL

A WAStays superadmin adds the relay at `/admin/webhook_endpoints`:

| Field | Meaning |
| --- | --- |
| **Friendly Name** | Anything. Shown in the admin list. |
| **Webhook URL** | Where WAStays POSTs. Yours. |
| **Hotel** | One hotel, or blank for every hotel |
| **Events** | Which events you want, or blank for all of them |

There is a **Test Ping** button next to each saved endpoint that fires a dummy
payload at the URL, so you can confirm it arrives before wiring anything real.

> **Set Events deliberately.** Blank means every event, including ones you have
> no handler for. A relay that only sends staff replies should list only
> `concierge_staff_reply`.

### The envelope

Every webhook has the same shape:

```json
{
  "event": "<event name>",
  "sent_at": "2026-08-19T14:32:00Z",
  "data": { }
}
```

`sent_at` is when WAStays sent it, not when the thing happened. On a retry it is
the retry's timestamp.

### The event that matters here

**`concierge_staff_reply`** — a person at the hotel typed a reply in the inbox
and it needs to reach the guest on WhatsApp.

```json
{
  "event": "concierge_staff_reply",
  "sent_at": "2026-08-19T14:32:00Z",
  "data": {
    "message_id": 4471,
    "conversation_id": 88,
    "hotel_name": "Seaside",
    "hotel_whatsapp_number": "+60111222333",
    "guest_name": "Aisyah",
    "guest_phone": "+60123456789",
    "staff_name": "Farah",
    "body": "Checkout is at noon.",
    "sent_at": "2026-08-19T14:32:00Z"
  }
}
```

What to do with it:

```
1 ──▶ Send data.body
2 ──▶ to data.guest_phone
3 ──▶ from data.hotel_whatsapp_number
4 ──▶ Respond 200
```

`hotel_whatsapp_number` matters when one relay serves several hotels — it says
which of your numbers the guest expects to hear from. `staff_name` is available
if you want to prefix the message; WAStays does not add it to `body`.

### 🔁 Idempotency — read this one

`message_id` is stable. **A retried delivery arrives with the same
`message_id`.** If you have already sent that id, skip it.

Without this check, a temporary failure on your side means the guest receives
the same reply two, three, or five times.

Keep sent ids for at least an hour. WAStays gives up after 5 attempts, and the
backoff means the last one can land well after the first.

### How your status code is read

WAStays reads the response and acts on it:

| You return | WAStays does |
| --- | --- |
| `200`–`299` | Considers it delivered. Forgets it. |
| `400`–`499` | Logs it and **gives up**. Assumes you rejected it on purpose. |
| `500`+ | **Retries**, up to 5 attempts with growing gaps. |
| no response / timeout / connection refused | **Retries**, same as above. |

Timeout is 10 seconds to connect and 10 to read.

> **Return 200 the moment you have accepted the message**, then do the WhatsApp
> send in your own background work. Holding the connection open while you call
> Meta risks a timeout, which WAStays reads as failure and retries — so the
> guest gets the message twice.

> **Do not return 4xx for a temporary problem.** WAStays will not try again, and
> the staff member will see "sent" in their inbox while the guest gets nothing.
> If you are unsure, 500 is the safer wrong answer.

### The other events

These already existed and are unchanged. Listed so you know what a blank Events
field lets through:

```
booking_confirmed            booking_cancelled
booking_updated              booking_checked_in
booking_completed            housekeeping_completed
complaint_resolved           checkout_completed
check_in_confirmation        pre_arrival_notification
check_out_receipt_message    post_stay_review_request
in_stay_guest_messaging
```

---

## Until the relay handles it

The reply box in the WAStays inbox only opens for a WhatsApp conversation when
**both** are true:

```
✅ an endpoint exists for that hotel listening for concierge_staff_reply
✅ the guest has a phone number on file
```

Otherwise staff see a notice saying which one is missing, and cannot type. This
is deliberate: a reply box that files text nobody delivers is worse than no
reply box, because staff believe they have answered.

So registering the endpoint is what switches the feature on for staff. Register
it only once the relay can actually handle the event.

---

## Checklist for building it

```
Inbound
  ☐ POST guest messages to the inquiries endpoint
  ☐ Send reply_message back to the guest
  ☐ Send NOTHING when reply_message is null
  ☐ Do not retry 401 / 403 / 422

Outbound
  ☐ Accept POST at your URL
  ☐ Handle event == "concierge_staff_reply"
  ☐ Send data.body to data.guest_phone from data.hotel_whatsapp_number
  ☐ Skip a message_id you have already sent
  ☐ Return 200 fast, send in the background
  ☐ Return 500 (not 4xx) for anything temporary

Then
  ☐ Register the URL at /admin/webhook_endpoints
  ☐ Set Events to concierge_staff_reply
  ☐ Set Hotel, unless the relay serves all of them
  ☐ Test Ping
```

---

## Where this lives in WAStays

For anyone who does need the code:

| Piece | File |
| --- | --- |
| Inbound API | `app/controllers/api/v1/ai_concierge/inquiries_controller.rb` |
| The silence when staff hold a thread | `app/services/ai_concierge/orchestration/turn_orchestrator.rb` |
| Building the staff-reply payload | `app/services/concierge/deliver_staff_reply.rb` |
| Choosing who receives an event | `app/models/webhook_endpoint.rb` |
| The POST, retries, status handling | `app/jobs/webhook_delivery_job.rb` |
| Whether the reply box opens | `app/models/conversation.rb` (`reply_blocker`) |
