# Edge: Hotel Knowledge Routing Ambiguity

## `InformationIntentGuard` Scenarios

1. `may i know hotel amenities` -> hotel information, not room information
2. `available facilities?` -> hotel information, not room information
3. `what amenities does the executive suite have` -> room information, not hotel information
4. hotel amenities after a completed booking returns hotel amenities, not room-type fallback
5. `tell me about the executive suite` vs `i want executive suite on may 22`: first is room info, second is booking flow
6. `do you have house rules?` -> hotel policy, not booking flow
7. `may i know if the hotel provide transportation` -> hotel information, not booking flow
8. `is parking available there?` -> hotel information, not booking flow
9. `do you have rooms available in july?` -> booking flow, not hotel information
10. `can i book parking view room on june 23?` -> booking flow, not hotel information
11. `what is room rate?` / `what is room price?` / `how much is the room?` -> booking flow, not hotel information
12. `how much is room service?` -> hotel information, not booking flow

## Contrast Examples

| Query | Expected Routing |
|-------|-----------------|
| `tell me about executive suite` | room information |
| `i want executive suite on may 22` | booking flow |
| `may i know hotel amenities` | hotel information |
| `available facilities?` | hotel information |
| `do you have house rules?` | hotel policy |
| `may i know if the hotel provide transportation` | hotel information |
| `is parking available there?` | hotel information |
| `do you have rooms available in july?` | booking flow |
| `can i book parking view room on june 23?` | booking flow |
| `what is room rate?` | booking flow |
| `what is room price?` | booking flow |
| `how much is the room?` | booking flow |
| `how much is room service?` | hotel information |
| `what attractions are nearby` | nearby attractions |
| `what time is check in` | hotel policy |

## Black-Box Category Retrieval

Hotel knowledge document categories are not reliable user-intent labels. When a hotel knowledge question is routed to one category but no useful answer is found, retrieval should retry across:

- `general_info`
- `faq`
- `policy`

Examples:

1. parking content stored under FAQ can answer `is parking available there?`
2. transportation content stored under general info can answer `does the hotel provide transportation?`
3. house rules content stored under policy can answer `do you have house rules?`

The expected failure mode is an unavailable hotel-knowledge reply, not a booking prompt with `request_quote`.
