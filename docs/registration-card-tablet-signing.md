# Signing a registration card on a front-desk tablet

**Who this is for:** whoever picks this up next — to extend it, to harden it, or
to work out why a tablet is sitting there doing nothing.

**Status: spike.** The loop works and is covered by specs, but the design has
not yet met a real tablet in a real lobby. Expect the pairing model and the
queue semantics to move once it has. See *What is proven* near the end for the
line between what is tested and what is not.

---

## Why the tablet cannot simply be opened

The feature is usually described backwards: *"staff click a button on the PC and
the tablet opens the form."* A server cannot do that. Nothing can push a page to
a browser that is not already talking to it.

So the model is inverted:

> The tablet is **already** sitting on a page holding an open WebSocket,
> waiting. The button on the PC does not open anything — it sends a message
> down that already-open socket, and **the tablet navigates itself.**

Everything else follows from this. In particular: a tablet that is asleep,
backgrounded, or has quietly lost its socket receives nothing at all, and the
desk has no way of knowing. That is the failure mode this feature lives or dies
by, which is why the idle screen states its connection out loud rather than
looking identical whether it is listening or not.

```
    PC (staff)                    server                    tablet (parked)
        │                            │                            │
        │                            │◀───── turbo_stream_from ────│  socket held open
        │                            │                            │
        │── POST signing_handoff ───▶│                            │
        │                            │── broadcast: "go to /next"─▶│
        │                            │                            │── Turbo.visit
        │                            │◀──────── GET /next ─────────│
        │                            │── 302 to the card page ───▶│
        │                            │                            │
        │                            │◀──── PATCH (signature) ─────│
        │                            │── 302 back to /next ──────▶│   next guest,
        │                            │                            │   or idle
```

## The pieces

| File | What it is |
| --- | --- |
| `app/models/signing_device.rb` | The tablet. Holds the token, the stay in hand, and the queue logic. |
| `app/controllers/hotel_portal/signing_devices_controller.rb` | Enrolment. Mints the token, then signs the staff member out. |
| `app/controllers/public/signing_devices_controller.rb` | The tablet's own two pages: `show` (idle) and `next` (advance). |
| `app/controllers/hotel_portal/bookings/signing_handoffs_controller.rb` | The PC-side push. |
| `app/services/signing/hand_stay_to_device.rb` | The broadcast itself. |
| `app/views/public/signing_devices/show.html.erb` | The idle screen. Holds the stream open. |
| `app/views/public/signing_devices/_command.html.erb` | The one region the desk may write to. |
| `app/javascript/controllers/signing_command_controller.js` | Navigates when that region is replaced. |
| `app/javascript/controllers/signing_kiosk_controller.js` | Says whether the socket is actually up, and beats that back to the server. |
| `app/helpers/hotel_portal/signing_devices_helper.rb` | How a tablet reads in the desk's picker: ready, busy, or not connected. |

No custom ActionCable channel: Turbo's built-in `Turbo::StreamsChannel` does the
work, which is why there is still no `app/channels` directory.

The signing page itself is **not** new. The tablet is sent to
`/guest-registration-card/:token` — the same page a guest opens from their own
phone. That is deliberate: one signing surface to build and to test, rather than
two that have to agree with each other.

## Enrolling a tablet

Done **on the tablet**, once, by someone who can manage bookings:

1. Open `/hotel/:hotel_id/signing_device/new` on the tablet and sign in.
2. Name it — "Front desk tablet", "Lobby" — and tap **Use this tablet**.
3. The tablet is redirected to `/signing-device/:token` and **the staff session
   is destroyed**.
4. Leave it on that page. That is its resting state.

Step 3 is the whole security model, not a courtesy. What is left on the counter
holds a device token and nothing else, so a guest who wanders off the page
cannot reach bookings, folios or guest records. `reset_session` is doing that
work, and there is a spec asserting the portal is unreachable afterwards — if
that spec ever goes green while the session survives, the feature is unsafe.

Enrolling again adds another tablet rather than replacing one. Once a property
has more than one, the footer button grows a picker.

## Trying it locally

Two prerequisites, both of which the handoff refuses without: the hotel needs
**registration card terms** (Settings → General), and the booking needs at least
two unsigned guests, so the queue visibly advances.

Then the part that catches everyone: **enrolment destroys the staff session**,
so enrolling in the browser you are using as the front desk logs you out of the
portal. Use a normal window as the PC and an incognito window as the tablet.

```
bin/dev

incognito  →  /hotel/:hotel_id/signing_device/new, sign in, name it, enrol
              land on /signing-device/:token, signed out. Leave it in the
              FOREGROUND -- it must say "Ready", not "Not connected".
normal     →  booking workspace, Guest details tab, Send to tablet
```

`config/cable.yml` uses `adapter: async` in development, which is **in-process
only**. One `bin/rails server` is fine; a broadcast triggered from `bin/rails
console` in a terminal reaches nothing, because that is a different process.

For a real tablet on the LAN: `bin/rails s -b 0.0.0.0`, then browse to your
machine's IP. Development `config.hosts` already permits IP addresses, so
nothing needs configuring. This is worth doing — see the status note at the top.

## What the queue is

There is no stored queue. `SigningDevice#current_booking` is the entire state,
and the next card is derived: whichever of that stay's guests has not signed
yet, primary first, then the rest in the order they were added.

Deriving it rather than storing it buys three things for free:

- a card signed somewhere else — the guest's own phone, the front desk — simply
  drops out of the queue
- a guest who walks away mid-signature is still next when the tablet comes back
- there is no list to get out of step with the booking

When nothing is left, `next` clears `current_booking` and sends the tablet back
to idle. The release happens **before** the redirect, so the screen cannot be
nudged back into someone's registration card afterwards.

## Why a busy tablet is refused

`SigningDevice#busy?` is the stay in hand still owing signatures — derived, like
the queue, so a tablet left on a stay whose guests all signed elsewhere frees
itself with nobody clearing it.

The handoff refuses a tablet that is busy with a **different** stay. That is not
politeness; without it the push silently loses a guest. The person standing at
the tablet is on the card page, which does **not** subscribe to the device
stream, so a stolen tablet does not move under them — they finish signing
undisturbed, and are then sent to `next`, which now derives from the *new*
booking. Whoever was left on the old one drops out of the queue with no error
anywhere. Staff saw "Sent" both times.

Pushing the **same** stay again is allowed, and is a retry rather than a
conflict: the usual reason for a second press is a tablet that slept through the
first. The busy check therefore runs *before* `nothing_to_sign?`, which assigns
the stay in memory to ask its question and would otherwise make every tablet
look busy with the booking being handed over.

## How the desk knows a tablet is listening

`last_seen_at` used to be written only when the idle screen loaded, which
answers the wrong question: a tablet that loaded the page and then died still
looked freshly seen. So the idle screen now POSTs to
`/signing-device/:token/heartbeat` every 20 seconds, and **only while its stream
is genuinely connected** — the beat and the on-screen status read the same
`connected` attribute, so they cannot disagree. `SigningDevice#live?` is three
missed beats (`LIVENESS_WINDOW`).

The picker labels a tablet *busy* or *not connected*, but this is advisory: the
handoff re-checks, and the state can go stale between renders.

A quiet tablet is **warned about, not refused**. A beat can fail for reasons the
tablet itself would survive, and a hard refusal would brick the feature every
time it did, so the push goes out and the flash says plainly that the tablet has
not checked in.

## What is on the wire

Only a path. The broadcast says *"go to `/signing-device/:token/next`"* — it
carries no card token and no guest details. The tablet fetches those itself, in
its own request, over HTTPS.

So anything able to overhear a device's stream learns which tablet is busy and
nothing whatsoever about who is signing. There is a spec asserting the card
token is absent from the payload; keep it that way if you change the broadcast.

The device token travels in the tablet's **session**, not in the URL, so it
never appears on the screen a guest is looking at and cannot be captured from a
shared or pasted link. The card page reads it back scoped to that card's own
hotel, so a stale session cannot steer one property's tablet from another's
card.

## Privacy, and why the screen clears itself

A lobby tablet showing the previous guest's passport number, address and TIN is
a PDPA problem, not a cosmetic one. Two things keep it clean:

- signing redirects **away** from the card immediately — to the next guest, or
  to idle
- the idle screen shows the hotel name and the device label, and no guest
  anything

Not yet handled: a guest who starts signing and wanders off leaves their card on
screen indefinitely. See the gaps below.

## What is proven, and what is not

**Covered by specs:**

- `spec/requests/hotel_portal/signing_devices_spec.rb` — enrolment, the staff
  sign-out, kiosk reachable with no session, the heartbeat keeping a tablet
  live without a session, and going stale once the beats stop
- `spec/requests/hotel_portal/signing_handoffs_spec.rb` — the push, the
  broadcast payload, cross-property refusal, the refusals (nothing to sign; no
  terms configured; a tablet busy with another stay), the same-stay retry, a
  busy tablet freeing itself when that stay signs elsewhere, and the warning
  on a tablet that has gone quiet
- `spec/system/hotel/signing_device_handoff_spec.rb` — a real browser walking
  two guests: card → sign → next card → sign → idle, device released

**If that system spec starts failing at the second guest, read this first.**
Both cards carry a signature pad, so `have_css(SIGNATURE_PAD)` matches the page
being navigated *away* from and the signer-name assertion beneath it then reads
the old form — a pass or fail decided by how fast Turbo swaps. The spec now
waits on `have_no_current_path` first, because the path is the only thing that
differs while the swap is in flight. Do not "fix" a recurrence by asserting
harder on the pad; assert on something that actually changes between the two
cards.

Two things that will otherwise waste an afternoon when this suite looks broken:

- **Do not run several `rspec` processes against the test database at once.**
  They share one database and produce failures that look like real races in
  whatever you happen to be working on.
- **The neighbouring `booking_workspace_*` system specs are independently
  flaky** — a different subset failed on each run here (6, then 4), and none of
  them creates a signing device, so nothing in the footer's tablet block even
  executes inside them. They are not evidence that this feature broke
  something.

**Not covered, and you should know why:** the socket hop itself. The test
environment's cable adapter (`config/cable.yml`) *records* broadcasts rather
than delivering them, and 19 assertions across 5 existing spec files depend on
that behaviour through the `turbo_broadcasts_to` helper
(`spec/support/turbo_broadcast_helpers.rb`) — so switching it to `async` to get
real delivery would break them.

The two halves are therefore tested on either side of the wire: the request spec
asserts what is broadcast, the system spec asserts what the tablet does when it
arrives at that path. **The hop between them needs a real device.** If you ever
do want it end to end in CI, the move is a separate cable configuration for
system specs only — not a global flip.

## Gaps before this ships

Roughly in the order they will bite:

1. **No abandonment timeout.** A card left open stays open. It wants a timer on
   the card page that returns the tablet to idle after a few quiet minutes.
2. **No way to recall a tablet.** `Signing::HandStayToDevice.release` exists and
   is unused — nothing in the UI calls it yet. Worse, it would not work on the
   case it was written for: a guest who has wandered off is sitting on the
   **card** page, which does not subscribe to the device stream, so the
   broadcast reaches nobody. It can only recall a tablet already on its idle
   screen, which needs no recalling.

   The fix unlocks three of these at once: **subscribe the card page to the
   device stream too.** Then release works, a takeover can move a guest off
   mid-card, and the abandonment timeout below has somewhere to send the
   tablet. Until then the busy refusal is what stands in for it.
3. **Nothing tells the PC that signing finished.** Staff push, then guess. The
   return leg wants a broadcast to the workspace so the footer updates itself.
4. **Devices cannot be renamed or revoked.** No settings screen; a lost tablet's
   token is valid until the row is deleted by hand. This is the one to fix
   before a real property uses it.
5. **No audit trail of pushes.** Who sent which stay to which tablet, and when,
   is not recorded anywhere.
6. **Terms are required.** A property with no registration card terms cannot use
   this at all — the card page refuses to collect a signature without them, so
   the handoff refuses up front and says so.

## The alternative worth remembering

A QR code on the PC screen, scanned by the guest's own phone, reaches the same
signing page with no pairing, no tablet to own, no shared-device privacy problem
and no socket to keep alive. It costs a guest with a working camera phone.

The two are not exclusive, and the honest framing is that the tablet is the
fallback for the QR rather than the other way round. Worth weighing again before
investing in the gaps above.
