# Room Type Details Tool

## `get_room_type_details`

- Path: `app/services/ai_concierge/tools/room_information/get_room_type_details_tool.rb`
- Purpose: answer room detail questions
- Inputs: guest message and optional interpreted `room_type_name`
- Success output: matched room type, description, occupancy, and amenity names
- Failure output: `ambiguous_room_type`, `room_type_not_found`
- Uses shared `RoomTypeMatcher` for fuzzy resolution

## Room Matching Behavior

1. exact normalized room-name match
2. fuzzy token and prefix matching against the guest message
3. ambiguous match result when multiple room types fit
4. not-found result when no room type matches

Examples:
- `exec suite` -> `Executive Suite`
- `ocean villa` -> ambiguous if both `Ocean Villa King` and `Ocean Villa Twin` exist
- `tell me about the executive suite`
- `what amenities does the ocean villa have`
