# Booking Flow State Machine

## Transition Rules

High-level transition order:

1. explicit or active-booking natural cancellation -> reset booking task and ask the next-step choice
2. explicit stop/bye/thanks/nevermind message -> end or confirm ending the current conversation
3. explicit reset -> reset current flow
4. non-expired suspended booking selection or confirmation follow-up -> resume booking
5. hotel-policy, hotel-information, nearby-attractions, or room-information intent -> librarian
6. booking context intent -> booking context
7. pending booking question -> booking
8. greeting intent -> greeting
9. booking, option-selection, or confirmation intent -> booking
10. unknown intent without state -> fallback

## Booking Sub-step Rules (inside `Booking::Orchestrator` and booking handlers)

1. no date window or concrete dates -> ask for booking timing: `Sure, which date or month do you plan to arrive for check-in?`
   - room rate/price questions with no active booking branch use a rate-specific timing prompt: `Dear guest, room rates depend on the booking dates and room types. Which date or month do you plan to arrive for check-in?`
2. vague month without specific date or segment -> ask for specific timing (early/mid/late)
3. explicit date ranges with a month -> derive `check_in`, `check_out`, `nights`, and `days`
4. monthless date ranges such as `16-18` -> ask which month and keep the pending range
5. pending date-range month replies such as `this month`, `next month`, `3 months from now`, or `June` -> resolve the stored range and continue slot collection
6. booking timing exists but duration missing -> ask duration
7. children exist without adults -> ask adult count
8. guest count missing -> ask guest count
9. `party_size_total` exists but adult/children split missing -> ask clarification (smart split with remainder suggestion)
10. valid option selection with multiple rate plans -> ask which rate plan
11. valid option selection with single/no rate plan -> auto-select, set `confirmation_candidate`, ask for confirmation
12. valid deterministic rate plan selection -> set `selected_rate_plan_id/name`, set `confirmation_candidate`, ask for confirmation
13. confirmation `yes` -> generate booking link and end the current conversation when URL generation succeeds
14. confirmation `no` -> clear candidate and return to option selection
15. failed booking URL generation -> return safe fallback and leave booking uncompleted
16. hotel-policy or information question during booking -> librarian answer with booking task suspended
17. return with option selection -> resume suspended branch if still valid
18. `another booking` -> archive completed branch and start fresh branch
19. change of month/window or party composition -> clear stale suggestions, pending selection, and confirmation state, then rerun search
20. generic booking request after stale no-options state -> reset stale branch and ask for fresh dates/month
21. bare `this month` without date or early/mid/late -> ask for exact check-in date or assumption range
22. booking-ready `change rate` / `show rates again` -> preserve selected room/date option, clear selected rate-plan state and confirmation candidate, then ask rate-plan selection when multiple rates exist
23. booking-ready `change room` / `different option` -> preserve timing, duration, guest composition, room count, and suggested options; clear selected option/rate/candidate; ask option selection or resolve the newly named option in the same turn

## Booking-Ready Revision Rules

A booking branch is booking-ready for scoped revision when it already has timing, duration, guest composition, room count, and `suggested_options`.

- rate revisions keep `selected_option` and upstream booking slots
- rate revisions clear `selected_rate_plan_id`, `selected_rate_plan_name`, and `confirmation_candidate`
- rate revisions with one/no available rate plan re-ask confirmation instead of cancelling
- option revisions keep timing, duration, guests, room count, and `suggested_options`
- option revisions clear `selected_option`, `selected_rate_plan_id`, `selected_rate_plan_name`, `confirmation_candidate`, and `pending_selection`
- same-turn option revisions can select a new room/date option immediately
- timing, duration, guest, or room-count changes remain broader corrections and clear downstream search/selection state
- explicit cancellation remains separate from revision and resets the booking task

## V4.1+ Hardening Rules

- booking URL generation validates required option fields and dates before quote creation
- failed booking URL generation returns a safe fallback and keeps the booking uncompleted
- room rate/price/cost questions such as `what is room rate?`, `what is room price?`, and `how much is the room?` are force-routed to booking so rates are quoted only after date/month and room-type context is collected
- service-price questions such as `how much is room service?` remain hotel-information questions, not booking starts
- room-type matching supports reordered shorthand, common aliases, suffix/plural normalization, and small typos while preserving ambiguity prompts
- rate-plan matching supports ordinals, price intent, `standard`, and refundable/non-refundable wording
- ambiguous rate-plan matching re-asks instead of guessing
- timing or party changes clear selected rate-plan fields along with suggestions, pending selections, confirmation candidates, and selected options
- natural active-booking cancellation phrases such as `forget the room`, `changed my mind`, and `drop the reservation` cancel only the booking attempt
- booking-ready revision phrases such as `change rate` and `change room` revise only the relevant downstream booking state and do not cancel the booking attempt
- date-range parsing is deterministic and scoped to timing collection so unrelated two-number replies during party/guest clarification are not treated as dates

## Booking Task Statuses

- `idle`: no active booking task.
- `collecting_slots`: booking exists and is asking for timing, duration, guest count, or split details.
- `waiting_for_option_selection`: options were shown and the guest must choose.
- `waiting_for_rate_plan_selection`: option selected, guest must choose a rate plan.
- `waiting_for_confirmation`: a selected option with rate plan is waiting for yes/no confirmation.
- `suspended`: booking is preserved while an information/librarian turn is answered.
- `completed`: booking branch was completed and archived.
- `expired`: suspended booking is no longer resumable.
