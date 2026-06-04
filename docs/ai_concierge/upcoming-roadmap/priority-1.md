# Priority 1: Top Risks

## Remaining Risks
1. hotels may store policy/service facts in unexpected knowledge categories, so retrieval quality still depends on good content
2. multi-turn cancellation phrasing beyond the V4.1 natural-language set may need more product tuning
3. room-type aliases may still need hotel-specific synonym configuration for unusual provider names

## V3.1 Risks
1. rate plan name normalization across providers — some hotels may use non-standard naming

## V4 Risks
1. `message_type` is internal guidance only; Ruby guards remain the final authority
2. booking-advice phrases may overlap with actual booking requests and should stay covered by regression tests

## V4.1 Mitigated Risks
1. room-type matching supports reordered shorthand, aliases, suffix/plural normalization, and small typos
2. booking-link generation validates required quote inputs and returns safe fallback errors before completion
3. selected rate-plan fields are cleared with stale downstream booking state
4. compact summaries no longer expose stale shown options, rate plans, or selected-option summaries after cleanup
5. booking-attempt cancellation recognizes natural active-booking phrases such as `forget the room`, `changed my mind`, and `drop the reservation`
6. rate-plan matching supports ordinals, price intent, `standard`, and refundable/non-refundable distinctions

## V4.2 Mitigated Risks
1. weak or unanswered hotel knowledge turns create staff-facing diagnostics under the Hotel Knowledge domain
2. suspended rate-plan selection has black-box coverage, including hotel information interruptions and `the cheaper one` resume language
3. strong deterministic knowledge answers are covered to avoid noisy diagnostic creation

## V4.3 Mitigated Risks
1. booking-ready `change rate` requests revise rate-plan state without cancelling the booking attempt
2. booking-ready `change room` / `different option` requests preserve upstream booking context and return to option selection
3. scoped booking revisions work after hotel-information interruptions resume a suspended booking
4. cancellation and revision language are covered separately so `changed my mind` still cancels while `change room` does not

## Expansion Candidates
- hotel-policy interruption and resume (implemented — covered)
- booking context rendering (implemented — covered)
- correction handling (implemented — covered)
- another-booking branching (implemented — covered)
- booking-ready rate/option revision (implemented — covered)

## Future Work
- `ProspectProfileFact` integration for persistent guest memory
- Anonymous/incognito conversation state support
- Additional information tool groups (restaurants, spa, events)
- Multi-language support
- Voice interface support
