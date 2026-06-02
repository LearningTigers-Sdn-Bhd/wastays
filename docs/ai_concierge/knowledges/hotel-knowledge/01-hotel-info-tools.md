# Hotel Information Tools

## V3.4 Black-Box Category Routing

- `policy`, `faq`, and `general_info` are storage categories, not perfect user-intent labels
- Ruby first decides whether the message is booking flow or hotel knowledge
- Hotel knowledge retrieval first searches the routed category, then retries across `general_info`, `faq`, and `policy` before using structured fallback text
- This protects black-box hotel content placement, for example:
  - parking stored under FAQ can still answer a general hotel information route
  - transportation stored under general info can still answer service questions
  - house rules stored under policy can still answer policy/rules questions
- Clear booking language still stays booking, for example room availability, reserve/book/quote, and date/month booking requests

## V3.3 Hybrid Knowledge Search

- Policy, FAQ, and general-info tools accept the raw guest question as `query`
- Query-aware tools call `HotelKnowledges::SearchService` to retrieve relevant indexed chunks by hotel and category
- `HybridAnswerBuilder` retries all hotel knowledge categories before generic structured fallback when the routed category has no useful answer
- Hybrid answer modes:
  - `fallback`: direct structured facts or legacy full-document text
  - `deterministic`: one strong retrieved match
  - `synthesized`: multiple retrieved matches composed by `KnowledgeAnswerAgent`
  - `unavailable`: no useful source
- Guest-facing replies prefer `result["answer"]`
- `knowledge_matches` metadata is internal and should not be shown to guests
- Source titles/citations are not included in guest replies
- `InformationIntentGuard` force-routes policy phrasing such as "booking policy", "hotel rules", "house rules", "cancellation", "check in", and "check out" to `hotel_policy`
- `InformationIntentGuard` force-routes general hotel service questions such as parking, transportation, shuttle, WiFi, breakfast, restaurant, spa, pool, amenities, and facilities to `hotel_information` unless the message is clearly a booking request

## `get_hotel_policy`

- Path: `app/services/ai_concierge_v3/tools/hotel_information/get_hotel_policy_tool.rb`
- Purpose: answer hotel policy questions
- Inputs: hotel, optional `policy_topic`, optional `query`
- Source order: vector search over indexed policy chunks -> cross-category hotel knowledge retry -> full indexed policy document fallback -> `hotel.property_policy`
- Success output: `answer`, `answer_mode`, `policy_text`, structured policy fields, internal `knowledge_matches`
- Example: "what time is check in", "what is your cancellation policy", "may I know the booking policy?", "do you have house rules?"

## `get_general_hotel_info`

- Path: `app/services/ai_concierge_v3/tools/hotel_information/get_general_hotel_info_tool.rb`
- Purpose: return general hotel details
- Inputs: hotel, optional `query`
- Source order: vector search over indexed `general_info` chunks -> cross-category hotel knowledge retry -> structured hotel facts and amenities
- Output: `answer`, `answer_mode`, name, address, city, country, star rating, mapped hotel amenities, summary text, internal `knowledge_matches`
- Example: "tell me about the hotel", "where is the hotel located", "is parking available there?", "does the hotel provide transportation?"

## `get_hotel_faq`

- Path: `app/services/ai_concierge_v3/tools/hotel_information/get_hotel_faq_tool.rb`
- Purpose: return hotel FAQ content
- Inputs: hotel, optional `query`
- Source order: vector search over indexed FAQ chunks -> cross-category hotel knowledge retry -> full indexed FAQ document fallback
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
