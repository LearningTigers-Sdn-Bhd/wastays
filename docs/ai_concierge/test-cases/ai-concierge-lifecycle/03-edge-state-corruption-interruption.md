# Edge: State Corruption and Interruption

## Conversation Lifecycle

1. explicit end message (`stop`/`bye`/`thanks`/`nevermind`) ends the current conversation only
2. later valid inbound message reactivates ended state
3. booking URL generation marks the conversation ended
4. `end_conversation` has highest precedence over all other routing

## Suspended Booking

1. suspended booking selection or confirmation follow-up resumes booking
2. expired suspended booking task does not resume
3. multiple interruptions accumulate `interruption_count`

## State Guards

1. hallucinated `check_in` stripped from vague booking messages
2. hallucinated `month_segment` stripped from vague messages
3. invented duration from month-only messages is rejected
4. `2 people` does not become `adults=2` automatically
5. `days` and `nights` normalization with derived `check_out`
6. stale `suggested_options` cleared when timing or party composition changes
7. legacy `active` state normalizes into V2 `booking_task`

## Abandonment

1. explicit abandonment (`nevermind`, `forget it`) has absolute precedence over slot extraction
2. prevents "nevermind" from being misinterpreted as an option or room name
