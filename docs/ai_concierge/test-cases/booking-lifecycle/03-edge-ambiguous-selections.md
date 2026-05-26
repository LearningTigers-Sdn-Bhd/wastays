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
