# Bad: Unknown Queries

## Missing Data

1. unavailable state when no policy data exists
2. unavailable FAQ state when FAQ content is blank
3. empty booking-context state returns an empty list

## Room Not Found

1. `room_type_not_found` when no room type matches the query

## Bad Questions

1. unrelated questions that don't match any hotel information intent -> fallback
2. gibberish or nonsensical input -> fallback
