# Good: Happy Path Booking

## Scenario: Full booking flow

1. **vague booking + guest count only** -> ask booking timing
2. **room rate/price first** with no active booking branch -> ask booking timing with the room-rate-specific prompt
3. **month window** -> ask duration
4. **`2 people`** stays unresolved until adult/children split is given
5. **grouped room-type options** are rendered with price
6. **unique date reply** selects the shown option
7. **`i chose option 1`** works when option number is unambiguous
8. **confirmed option** returns booking URL with total and expiry
9. **completed booking -> `another booking`** starts a fresh branch

## Scenario: Booking with interruption

1. booking question -> hotel policy -> preserved options -> selection
2. booking flow -> `tell me about the executive suite` -> room details reply -> `option 2 please` resumes booking

## Scenario: Correction

1. `late july` -> `late may` correction invalidates old options

## Scenario: Public ID continuation

1. valid `prospect_public_id` continues the existing prospect conversation
2. new inbound message reactivates an ended conversation state
