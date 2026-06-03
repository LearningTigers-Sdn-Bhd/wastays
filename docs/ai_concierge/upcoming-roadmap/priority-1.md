# Priority 1: Top Risks

## Remaining Risks
1. room-type matching may still be too strict for natural shorthand not covered by current examples
2. booking-link generation can still fail when upstream quote/availability data lacks required IDs
3. hotels may store policy/service facts in unexpected knowledge categories, so retrieval quality still depends on good content
4. multi-turn cancellation phrasing beyond explicit cancel-attempt language may need more product tuning

## V3.1 Risks
1. interpreter may still miss unusual rate plan descriptions beyond common phrases such as "the cheaper one" or "first one"
2. rate plan name normalization across providers — some hotels may use non-standard naming
3. rate plan selection during suspended booking resume may lose context

## V4 Risks
1. `message_type` is internal guidance only; Ruby guards remain the final authority
2. compact state can become stale if shown options or rate-plan summaries are not cleared with branch changes
3. booking-advice phrases may overlap with actual booking requests and should stay covered by regression tests

## Expansion Candidates
- hotel-policy interruption and resume (implemented — verify coverage)
- booking context rendering (implemented — verify coverage)
- correction handling (implemented — verify coverage)
- another-booking branching (implemented — verify coverage)

## Future Work
- `ProspectProfileFact` integration for persistent guest memory
- Anonymous/incognito conversation state support
- Additional information tool groups (restaurants, spa, events)
- Multi-language support
- Voice interface support
