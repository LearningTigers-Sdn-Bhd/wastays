# Concierge provider evidence

Phase M. A live run of the conversation fixtures against every
configured provider — the first time these fixtures have reached a real
model rather than `ScriptedChat` / `ReferenceClassifier`.

- **Run on:** 2026-08-21 00:29 UTC
- **Fixtures:** 14 of 18 — the run was stopped early, so `resume_with_a_changed_search`, `resume_with_nothing_new`, `chinese_booking_ladder` and `malay_booking_ladder` were not measured
- **Command:** `CONCIERGE_LIVE=1 bundle exec rspec spec/ai_concierge/eval/live_provider_spec.rb`
- **Keys:** the platform `AppConfig` rows set at `/admin/integrations`.
- **Measured:** `openai` (gpt-4o-mini)
- **Not measured:** `claude`, `gemini` — no key in `AppConfig`, so these rows are blank rather than green

Scripted turns in the fixtures are ignored here by definition: the point
of a live run is that the model decides. Retrieval stays faked (the
fixture corpus, scored by word overlap) so what is being measured is the
model, not the index. The reply stylist and the knowledge synthesis both
run for real.

**This is not a gate.** The live spec is excluded from `bin/test` and
`bin/ci` unless `CONCIERGE_LIVE` is set. A red cell is a finding, not a
broken build.

## Matrix

| fixture | openai |
| --- | --- |
| asks_before_it_prices | pass |
| booking_advice_is_policy | pass |
| cancellation_is_policy | pass |
| guest_ends_the_conversation | pass |
| hotel_amenities_are_not_room_amenities | pass |
| model_invents_a_change | **fail** (2/8 turns) |
| model_misreads_the_answer | **fail** (1/5 turns) |
| party_split_before_search | **fail** (1/1 turns) |
| question_mid_booking_then_resume | **fail** (2/3 turns) |
| resume_picks_a_row | pass |
| room_rate_is_a_booking | pass |
| room_service_is_not_a_room_question | pass |
| service_question_is_hotel_information | pass |
| timing_to_quote | **fail** (4/5 turns) |

- `openai`: 9/14 fixtures clean, 27/37 turns clean

## Unscripted fixtures (9)

The regression reading: every turn here is a fair test of a provider reading a guest message cold.

- `booking_advice_is_policy` — openai: pass
- `cancellation_is_policy` — openai: pass
- `guest_ends_the_conversation` — openai: pass
- `hotel_amenities_are_not_room_amenities` — openai: pass
- `party_split_before_search` — openai: **fail** (1/1 turns)
- `question_mid_booking_then_resume` — openai: **fail** (2/3 turns)
- `room_service_is_not_a_room_question` — openai: pass
- `service_question_is_hotel_information` — openai: pass
- `timing_to_quote` — openai: **fail** (4/5 turns)

## Scripted fixtures (5)

These fixtures script the model, and five of them script it getting the answer **wrong**. A live run cannot honour that scripting, so a result here answers a different question: does this provider make the mistake at all? Never read these as regression results.

- `asks_before_it_prices` — openai: pass
- `model_invents_a_change` — openai: **fail** (2/8 turns)
- `model_misreads_the_answer` — openai: **fail** (1/5 turns)
- `resume_picks_a_row` — openai: pass
- `room_rate_is_a_booking` — openai: pass

## Failing turns

### `openai` · `model_invents_a_change` · turn 7

**Guest:** sounds good to me

**Reply:** Great, I've prepared your booking quote:
- Date: *28 August 2026 - 31 August 2026*
- Total: *RM 1,200.00*

Please note that the quotation link will expire at 12:42 AM.
Quotation link:
http://example.com/quotes/69f07617811d7320a985bf65b5cb7aed

Please let me know if you need anything.

```
expected: "confirm_selection"
     got: nil

(compared using ==)
```

### `openai` · `model_invents_a_change` · turn 8

**Guest:** yes

**Reply:** Could you please provide more details about what you need assistance with?

```
expected "Could you please provide more details about what you need assistance with?" to include "Quotation link:"
```

### `openai` · `model_misreads_the_answer` · turn 5

**Guest:** yes

**Reply:** Baik, saya telah menyediakan sebut harga tempahan anda:
- Tarikh: *28 Ogos 2026 - 31 Ogos 2026*
- Jumlah: *RM 663.00*

Sila ambil perhatian bahawa pautan sebut harga akan tamat pada 12:43 AM.
Pautan sebut harga:
http://example.com/quotes/b4651cbe4386080eda553d2e7eb16b30

Sila maklumkan kepada saya jika anda memerlukan apa-apa.

```
expected "Baik, saya telah menyediakan sebut harga tempahan anda:\n- Tarikh: *28 Ogos 2026 - 31 Ogos 2026*\n- ...quotes/b4651cbe4386080eda553d2e7eb16b30\n\nSila maklumkan kepada saya jika anda memerlukan apa-apa." to include "Quotation link:"
Diff:
@@ -1 +1,9 @@
-Quotation link:
+Baik, saya telah menyediakan sebut harga tempahan anda:
+- Tarikh: *28 Ogos 2026 - 31 Ogos 2026*
+- Jumlah: *RM 663.00*
+
+Sila ambil perhatian bahawa pautan sebut harga akan tamat pada 12:43 AM.
+Pautan sebut harga:
+http://example.com/quotes/b4651cbe4386080eda553d2e7eb16b30
+
+Sila maklumkan kepada saya jika anda memerlukan apa-apa.
```

### `openai` · `party_split_before_search` · turn 1

**Guest:** early august for 3 days 2 nights for 4 people

**Reply:** 1 August 2026 has already passed. Which date or month would you like to check in?

```
expected: "party_split"
     got: "booking_timing"

(compared using ==)
```

### `openai` · `timing_to_quote` · turn 1

**Guest:** early august for 3 days 2 nights

**Reply:** 1 August 2026 has already passed. Which date or month would you like to check in?

```
expected: "guest_count"
     got: "booking_timing"

(compared using ==)
```

### `openai` · `timing_to_quote` · turn 2

**Guest:** 2 adults

**Reply:** Sure, which date or month do you plan to arrive for check-in?

```
expected: "select_option"
     got: "booking_timing"

(compared using ==)
```

### `openai` · `timing_to_quote` · turn 3

**Guest:** option 1

**Reply:** I didn't catch that.

Sure, which date or month do you plan to arrive for check-in?

```
expected: "confirm_selection"
     got: "booking_timing"

(compared using ==)
```

### `openai` · `timing_to_quote` · turn 4

**Guest:** yes

**Reply:** Sure, which date or month do you plan to arrive for check-in?

```
expected "Sure, which date or month do you plan to arrive for check-in?" to include "Quotation link:"
```

### `openai` · `question_mid_booking_then_resume` · turn 1

**Guest:** early august for 3 days 2 nights

**Reply:** 1 August 2026 has already passed. Which date or month would you like to check in?

```
expected: "guest_count"
     got: "booking_timing"

(compared using ==)
```

### `openai` · `question_mid_booking_then_resume` · turn 3

**Guest:** 2 adults

**Reply:** Sure, which date or month do you plan to arrive for check-in?

```
expected: "select_option"
     got: "booking_timing"

(compared using ==)
```

## Cost and latency

Token counts come from the `AiConcierge::Usage` log line Phase J added —
no new instrumentation. Prices are list, 3-provider
snapshot taken 2026-08-21.

| provider | calls | input | cached | output | cached share | cost | p50 turn | slowest turn |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `openai` | 41 | 11635 | 8960 | 2062 | 77% | $0.0023 | 3.0s | 5.6s |

Cached share is the live check on Phase J's caching fix: claude writes an
explicit `cache_control` breakpoint, openai and gemini cache a prefix
automatically, and all three need the stable prompt to stay above the
provider's minimum. A share near zero means the prefix stopped earning
its keep.

## What this settles

`Hotel::AI_CONCIERGE_MODEL_NAMES` names one model per provider, and the
provider is a per-hotel setting — so the table above is three different
products, not three renderings of one. Read the matrix against the cost
column before changing that constant; the change itself is one line and
belongs in its own commit.

_Written by `spec/support/ai_concierge/live_report.rb`. Re-running the
live spec overwrites this file._