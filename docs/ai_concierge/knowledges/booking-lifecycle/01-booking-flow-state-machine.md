# Booking Flow State Machine

## Transition Rules

High-level transition order:

1. explicit stop/bye/thanks/nevermind message -> end the current conversation (highest precedence)
2. explicit reset -> reset current flow
3. non-expired suspended booking selection or confirmation follow-up -> resume booking
4. hotel-policy, hotel-information, nearby-attractions, or room-information intent -> librarian
5. booking context intent -> booking context
6. pending booking question -> booking
7. greeting intent -> greeting
8. booking, option-selection, or confirmation intent -> booking
9. unknown intent without state -> fallback

## Booking Sub-step Rules (inside `BookingOrchestrator`)

1. no date window or concrete dates -> ask for booking timing
2. vague month without specific date or segment -> ask for specific timing (early/mid/late)
3. booking timing exists but duration missing -> ask duration
4. children exist without adults -> ask adult count
5. guest count missing -> ask guest count
6. `party_size_total` exists but adult/children split missing -> ask clarification (smart split with remainder suggestion)
7. valid option selection with multiple rate plans -> ask which rate plan
8. valid option selection with single/no rate plan -> auto-select, set `confirmation_candidate`, ask for confirmation
9. valid rate plan selection -> set `selected_rate_plan_id/name`, set `confirmation_candidate`, ask for confirmation
10. confirmation `yes` -> generate booking link and end the current conversation when URL generation succeeds
11. confirmation `no` -> clear candidate and return to option selection
12. failed booking URL generation -> return safe fallback and leave booking uncompleted
13. hotel-policy or information question during booking -> librarian answer with booking task suspended
14. return with option selection -> resume suspended branch if still valid
15. `another booking` -> archive completed branch and start fresh branch
16. change of month/window or party composition -> clear stale suggestions, pending selection, and confirmation state, then rerun search

## Booking Task Statuses

- `idle`: no active booking task.
- `collecting_slots`: booking exists and is asking for timing, duration, guest count, or split details.
- `waiting_for_option_selection`: options were shown and the guest must choose.
- `waiting_for_rate_plan_selection`: option selected, guest must choose a rate plan.
- `waiting_for_confirmation`: a selected option with rate plan is waiting for yes/no confirmation.
- `suspended`: booking is preserved while an information/librarian turn is answered.
- `completed`: booking branch was completed and archived.
- `expired`: suspended booking is no longer resumable.
