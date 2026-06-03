# Edge: State Corruption and Interruption

## Conversation Lifecycle

1. explicit end message (`stop`/`bye`/`thanks`/`nevermind`) ends or confirms ending the current conversation only
2. later valid inbound message reactivates ended state
3. booking URL generation marks the conversation ended
4. `end conversation` is accepted as an explicit end command
5. booking attempt cancellation resets booking state and asks the next-step choice instead of ending immediately

## Suspended Booking

1. suspended booking selection or confirmation follow-up resumes booking
2. expired suspended booking task does not resume
3. multiple interruptions accumulate `interruption_count`
4. hotel policy/info/advice questions do not resume a suspended booking just because stale booking state exists

## State Guards

1. hallucinated `check_in` stripped from vague booking messages
2. hallucinated `month_segment` stripped from vague messages
3. invented duration from month-only messages is rejected
4. `2 people` does not become `adults=2` automatically
5. `days` and `nights` normalization with derived `check_out`
6. stale `suggested_options` cleared when timing or party composition changes
7. legacy `active` state normalizes into V2 `booking_task`
8. `late this month` uses the current calendar month
9. bare `this month` clears stale `early/mid/late` and asks for a date or assumption range
10. generic `I want to make booking` after stale no-options state starts fresh

## Abandonment

1. explicit abandonment (`nevermind`, `forget it`) has precedence over slot extraction
2. prevents "nevermind" from being misinterpreted as an option or room name
3. cancel-attempt language clears booking attempt and asks whether to start booking, ask hotel info/policy, or end
