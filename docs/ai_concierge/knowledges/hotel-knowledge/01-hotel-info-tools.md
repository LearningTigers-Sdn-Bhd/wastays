# Hotel Information Tools

## `get_hotel_policy`

- Path: `app/services/ai_concierge_v3/tools/hotel_information/get_hotel_policy_tool.rb`
- Purpose: answer hotel policy questions
- Source order: `hotel.policy` -> fallback to `hotel.property_policy`
- Success output: policy_text and/or structured policy fields
- Example: "what time is check in", "what is your cancellation policy"

## `get_general_hotel_info`

- Path: `app/services/ai_concierge_v3/tools/hotel_information/get_general_hotel_info_tool.rb`
- Purpose: return general hotel details
- Inputs: hotel only
- Output: name, address, city, country, star rating, mapped hotel amenities, summary text
- Example: "tell me about the hotel", "where is the hotel located"

## `get_hotel_faq`

- Path: `app/services/ai_concierge_v3/tools/hotel_information/get_hotel_faq_tool.rb`
- Purpose: return hotel FAQ content
- Inputs: hotel only
- Output: faq_text
- Example: "do you have an faq", "what does your faq say"

## `get_nearby_attractions`

- Path: `app/services/ai_concierge_v3/tools/hotel_information/get_nearby_attractions_tool.rb`
- Purpose: return the full nearby attractions list
- Inputs: hotel only
- Output: all nearby attractions with name, description, address, city, and country
- Example: "what attractions are nearby", "what is around the hotel"

## `get_booking_context`

- Path: `app/services/ai_concierge_v3/tools/hotel_information/get_booking_context_tool.rb`
- Purpose: answer questions about an existing active booking for the resolved prospect phone number
- Output: structured booking rows with date range and room type name
- Example: "what booking do i have", "do i have an active booking"
