# Hotel Information Tools

## V3.3 Hybrid Knowledge Search

- Policy, FAQ, and general-info tools accept the raw guest question as `query`
- Query-aware tools call `HotelKnowledges::SearchService` to retrieve relevant indexed chunks by hotel and category
- Hybrid answer modes:
  - `fallback`: direct structured facts or legacy full-document text
  - `deterministic`: one strong retrieved match
  - `synthesized`: multiple retrieved matches composed by `KnowledgeAnswerAgent`
  - `unavailable`: no useful source
- Guest-facing replies prefer `result["answer"]`
- `knowledge_matches` metadata is internal and should not be shown to guests
- Source titles/citations are not included in guest replies
- `InformationIntentGuard` force-routes policy phrasing such as "booking policy", "hotel rules", "cancellation", "check in", and "check out" to `hotel_policy`

## `get_hotel_policy`

- Path: `app/services/ai_concierge_v3/tools/hotel_information/get_hotel_policy_tool.rb`
- Purpose: answer hotel policy questions
- Inputs: hotel, optional `policy_topic`, optional `query`
- Source order: vector search over indexed policy chunks -> full indexed policy document fallback -> `hotel.property_policy`
- Success output: `answer`, `answer_mode`, `policy_text`, structured policy fields, internal `knowledge_matches`
- Example: "what time is check in", "what is your cancellation policy", "may I know the booking policy?"

## `get_general_hotel_info`

- Path: `app/services/ai_concierge_v3/tools/hotel_information/get_general_hotel_info_tool.rb`
- Purpose: return general hotel details
- Inputs: hotel, optional `query`
- Source order: vector search over indexed `general_info` chunks -> structured hotel facts and amenities
- Output: `answer`, `answer_mode`, name, address, city, country, star rating, mapped hotel amenities, summary text, internal `knowledge_matches`
- Example: "tell me about the hotel", "where is the hotel located"

## `get_hotel_faq`

- Path: `app/services/ai_concierge_v3/tools/hotel_information/get_hotel_faq_tool.rb`
- Purpose: return hotel FAQ content
- Inputs: hotel, optional `query`
- Source order: vector search over indexed FAQ chunks -> full indexed FAQ document fallback
- Output: `answer`, `answer_mode`, `faq_text`, internal `knowledge_matches`
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
