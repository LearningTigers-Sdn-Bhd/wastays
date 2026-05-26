# Edge: Amenity Routing Ambiguity

## `InformationIntentGuard` Scenarios

1. `may i know hotel amenities` -> hotel information, not room information
2. `available facilities?` -> hotel information, not room information
3. `what amenities does the executive suite have` -> room information, not hotel information
4. hotel amenities after a completed booking returns hotel amenities, not room-type fallback
5. `tell me about the executive suite` vs `i want executive suite on may 22`: first is room info, second is booking flow

## Contrast Examples

| Query | Expected Routing |
|-------|-----------------|
| `tell me about executive suite` | room information |
| `i want executive suite on may 22` | booking flow |
| `may i know hotel amenities` | hotel information |
| `available facilities?` | hotel information |
| `what attractions are nearby` | nearby attractions |
| `what time is check in` | hotel policy |
