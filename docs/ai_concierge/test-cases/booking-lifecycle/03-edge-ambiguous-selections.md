# Edge: Ambiguous Selections

## Scenario: Ambiguous room type

1. partial room type matches like `garden prestige` and `executive` across multiple room types
2. `ocean villa` ambiguous when both `Ocean Villa King` and `Ocean Villa Twin` exist

## Scenario: Ambiguous date

1. ambiguous date follow-up prompts with matching room type names
2. room type reply after ambiguous date does not loop

## Scenario: Ambiguous option

1. ambiguous option-number selections ask for room type clarification
2. room-type-only selection when exactly one visible option exists -> selects directly

## Scenario: Pending date context

1. pending date context resolves room-type follow-ups without looping
2. combined room-type and date selection in one message

## Scenario: Raw option phrases

1. `i chose option 1`, `i choose option 1`, `choice 1`, `number 1` all accepted

## Scenario: Message type depends on state

1. `yes` while pending confirmation confirms the selected option
2. `yes` while pending guest count does not confirm booking
3. `option 1 executive` while shown options exist selects the shown option
4. `the cheaper one` while rate plans are shown selects the cheaper rate plan
5. `what about deluxe?` after shown options uses compact shown-option context

## Scenario: Rate-plan black-box coverage

1. multiple rate plans shown, `first one` selects the first displayed plan
2. multiple rate plans shown, `cheapest` selects the unique lowest-priced plan
3. hotel policy/info interruption during `rate_plan_selection` suspends booking and `the cheaper one` resumes it
4. `refundable` does not select `Non-Refundable Rate`
5. ambiguous `standard` re-asks the rate-plan question instead of guessing
6. selected rate plan is preserved in `confirmation_candidate`
7. selected rate plan state clears when date or party slots change
