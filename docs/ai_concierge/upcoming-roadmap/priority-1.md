# Priority 1: Top Risks

## Remaining Risks
1. interpreter invents month or date from vague booking interest
2. interpreter invents duration from month-only messages
3. interpreter converts `people` into `adults`
4. stale option sets survive corrections
5. disambiguation loops if pending selection context is not preserved
6. room-type matching is too strict for natural shorthand
7. booking-link generation fails because selected options lack `room_type_id`

## V3.1 Risks
1. interpreter fails to extract rate plan name from vague guest descriptions ("the cheaper one", "first one")
2. rate plan name normalization across providers — some hotels may use non-standard naming
3. rate plan selection during suspended booking resume may lose context

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

