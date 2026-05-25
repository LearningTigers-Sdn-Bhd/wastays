require "rails_helper"

RSpec.describe "API V1 AI Concierge Inquiries", type: :request do
  let(:hotel) { create(:hotel, :with_ai_concierge) }
  let(:api_key) { create(:api_key, bearer: hotel) }
  let(:headers) { { "Authorization" => "Bearer #{api_key.token}", "Content-Type" => "application/json" } }
  let(:path) { "/api/v1/hotels/#{hotel.id}/ai_concierge/inquiries" }
  let(:slug_path) { "/api/v1/hotels/#{hotel.slug}/ai_concierge/inquiries" }
  let(:phone) { "0123456789" }

  before do
    create(:property_policy, hotel: hotel, check_in_time: "15:00", check_out_time: "12:00", cancellation_policy: "24 hours")
    create(:guest, phone: "+60123456789")
    stub_interpreter
  end

  describe "POST /api/v1/hotels/:hotel_id/ai_concierge/inquiries" do
    it "returns 401 without authorization" do
      post path, params: { message: "Hello", phone: phone }.to_json, headers: { "Content-Type" => "application/json" }

      expect(response).to have_http_status(:unauthorized)
      expect(parsed_body["error"]).to include("Unauthorized")
    end

    it "returns 403 for a hotel not owned by the API key" do
      other_hotel = create(:hotel)
      other_path = "/api/v1/hotels/#{other_hotel.id}/ai_concierge/inquiries"

      post other_path, params: { message: "Hello", phone: phone }.to_json, headers: headers

      expect(response).to have_http_status(:forbidden)
      expect(parsed_body["error"]).to include("Forbidden")
    end

    it "returns 422 when message is blank" do
      post path, params: { message: "", phone: phone }.to_json, headers: headers

      expect(response).to have_http_status(:unprocessable_content)
      expect(parsed_body["error"]).to eq("Message is required")
    end

    it "returns 422 when message exceeds max length" do
      long_message = "x" * 2001

      post path, params: { message: long_message, phone: phone }.to_json, headers: headers

      expect(response).to have_http_status(:unprocessable_content)
      expect(parsed_body["error"]).to eq("Message is too long (max 2000 characters)")
    end

    it "answers hotel policy questions" do
      hotel.update!(policy: [
        {
          "title" => "Quiet Hours",
          "content" => "Quiet hours start at 10 PM."
        }
      ])

      post path, params: { message: "What is the policy of this hotel?", phone: phone }.to_json, headers: headers

      expect(response).to have_http_status(:ok)
      expect(parsed_body["reply_message"]).to eq("Welcome to #{hotel.name}! Quiet Hours: Quiet hours start at 10 PM.")
      expect(parsed_body["needs_human_support"]).to be(false)
      expect(parsed_body["action_name"]).to be_nil
      expect(parsed_body["prospect_public_id"]).to be_present
    end

    it "accepts hotel slugs in the path" do
      post slug_path, params: { message: "What is the policy of this hotel?", phone: phone }.to_json, headers: headers

      expect(response).to have_http_status(:ok)
      expect(parsed_body["reply_message"]).to include(hotel.name)
    end

    it "answers general hotel information questions" do
      post path, params: { message: "Tell me about the hotel", phone: phone }.to_json, headers: headers

      expect(response).to have_http_status(:ok)
      expect(parsed_body["reply_message"]).to include(hotel.name)
      expect(parsed_body["reply_message"]).to include(hotel.address)
      expect(parsed_body["reply_message"]).to include(hotel.city)
    end

    it "answers hotel faq questions" do
      hotel.update!(faq: [
        {
          "section_name" => "General",
          "items" => [
            {
              "question" => "What time is breakfast?",
              "answer" => "Breakfast is served daily from 7 AM to 10 AM."
            }
          ]
        }
      ])

      post path, params: { message: "Do you have an faq?", phone: phone }.to_json, headers: headers

      expect(response).to have_http_status(:ok)
      expect(parsed_body["reply_message"]).to eq("General\n- Q: What time is breakfast?\n  A: Breakfast is served daily from 7 AM to 10 AM.")
    end

    it "returns the full nearby attractions list" do
      create(:nearby_attraction, hotel: hotel, name: "Sky Bridge", description: "Scenic landmark", address: "Cable Car Station")
      create(:nearby_attraction, hotel: hotel, name: "Night Market", description: "Local food and shopping", address: "Town Square")

      post path, params: { message: "What attractions are nearby?", phone: phone }.to_json, headers: headers

      expect(response).to have_http_status(:ok)
      expect(parsed_body["reply_message"]).to include("Here are the nearby attractions")
      expect(parsed_body["reply_message"]).to include("Sky Bridge")
      expect(parsed_body["reply_message"]).to include("Night Market")
    end

    it "answers room information questions with fuzzy matching" do
      create(:room_type,
        hotel: hotel,
        name: "Executive Suite",
        description: "Large suite with sea view.",
        max_adults: 3,
        max_children: 2,
        amenities: %w[wifi balcony tv]
      )

      post path, params: { message: "Tell me about the exec suite", phone: phone }.to_json, headers: headers

      expect(response).to have_http_status(:ok)
      expect(parsed_body["reply_message"]).to include("Here are the details for Executive Suite")
      expect(parsed_body["reply_message"]).to include("Large suite with sea view.")
      expect(parsed_body["reply_message"]).to include("Amenities: Free WiFi, Balcony / Terrace, Flat-screen TV")
    end

    it "asks the guest to clarify when a room question matches multiple room types" do
      create(:room_type, hotel: hotel, name: "Ocean Villa King")
      create(:room_type, hotel: hotel, name: "Ocean Villa Twin")

      post path, params: { message: "Tell me about the ocean villa", phone: phone }.to_json, headers: headers

      expect(response).to have_http_status(:ok)
      expect(parsed_body["reply_message"]).to include("multiple room types")
      expect(parsed_body["reply_message"]).to include("Ocean Villa King")
      expect(parsed_body["reply_message"]).to include("Ocean Villa Twin")
    end

    it "preserves the selected month when the guest only answers duration" do
      post path, params: { message: "hello, any booking for early august?", phone: phone }.to_json, headers: headers
      post path, params: { message: "3 days 2 nights", phone: phone }.to_json, headers: headers

      expect(response).to have_http_status(:ok)
      expect(parsed_body["reply_message"]).to include("early August")
      expect(parsed_body["reply_message"]).to include("How many guests")
      expect(parsed_body["reply_message"]).not_to include("May")
    end

    it "asks when if the user only shares guest count" do
      post path, params: { message: "hello, is there any booking for 2 adults", phone: phone }.to_json, headers: headers

      expect(response).to have_http_status(:ok)
      expect(parsed_body["reply_message"]).to include("what dates or month")
      expect(parsed_body["reply_message"]).not_to include("May")
      expect(parsed_body["reply_message"]).not_to include("August")
    end

    it "asks for duration after the guest later provides a month window" do
      post path, params: { message: "hello, is there any booking for 2 adults", phone: phone }.to_json, headers: headers
      post path, params: { message: "early august", phone: phone }.to_json, headers: headers

      expect(response).to have_http_status(:ok)
      expect(parsed_body["reply_message"]).to include("How many days and nights")
    end

    it "preserves people as an unresolved split after the guest later provides duration" do
      post path, params: { message: "can i book for early june? for 2 people", phone: phone }.to_json, headers: headers
      post path, params: { message: "2 days 1 night", phone: phone }.to_json, headers: headers

      expect(response).to have_http_status(:ok)
      expect(parsed_body["reply_message"]).to include("For 2 people")
      expect(parsed_body["reply_message"]).to include("adults and how many are children")
    end

    it "renders grouped room type options" do
      seed_room_type_options("Garden Prestige Suite", month: 8, days: [ 1, 2, 3, 4 ])

      post path, params: { message: "hello, any booking for early august?", phone: phone }.to_json, headers: headers
      post path, params: { message: "3 days 2 nights", phone: phone }.to_json, headers: headers
      post path, params: { message: "2 adults", phone: phone }.to_json, headers: headers

      expect(response).to have_http_status(:ok)
      expect(parsed_body["reply_message"]).to include("Garden Prestige Suite")
      expect(parsed_body["reply_message"]).to include("1. *RM")
      expect(parsed_body["reply_message"]).to include("Check-in *1 August 2026* - Check-out *3 August 2026*")
      expect(parsed_body["reply_message"]).to include('Reply with the room type name and option number or date you want, for example: "Ocean Villa King option 1" or "Executive Penthouse on May 21"')
    end

    it "selects a unique shown option by date text" do
      seed_room_type_options("Garden Prestige Suite", month: 8, days: [ 1, 2, 3, 4 ])

      post path, params: { message: "hello, any booking for early august?", phone: phone }.to_json, headers: headers
      post path, params: { message: "3 days 2 nights", phone: phone }.to_json, headers: headers
      post path, params: { message: "2 adults", phone: phone }.to_json, headers: headers
      post path, params: { message: "August 3rd", phone: phone }.to_json, headers: headers

      expect(response).to have_http_status(:ok)
      expect(parsed_body["reply_message"]).to include("Garden Prestige Suite")
      expect(parsed_body["reply_message"]).to include("Please reply *Yes* to confirm the book and *No* to reconsider the choices.")
    end

    it "mentions room type names when a date is ambiguous across room types" do
      seed_room_type_options("Garden Prestige Suite", month: 8, days: [ 1, 2, 3, 4 ])
      seed_room_type_options("Deluxe Room", month: 8, days: [ 1, 2, 3, 4 ])

      post path, params: { message: "hello, any booking for early august?", phone: phone }.to_json, headers: headers
      post path, params: { message: "3 days 2 nights", phone: phone }.to_json, headers: headers
      post path, params: { message: "2 adults", phone: phone }.to_json, headers: headers
      post path, params: { message: "August 3rd", phone: phone }.to_json, headers: headers

      expect(response).to have_http_status(:ok)
      expect(parsed_body["reply_message"]).to include("Garden Prestige Suite")
      expect(parsed_body["reply_message"]).to include("Deluxe Room")
      expect(parsed_body["reply_message"]).to include("Please tell me which room type you want")
    end

    it "resumes the saved option set after a hotel policy interruption" do
      seed_room_type_options("Ocean Villa King", month: 5, days: [ 21, 22, 23, 24, 25, 26 ])
      seed_room_type_options("Executive Penthouse", month: 5, days: [ 21, 22, 23, 24, 25, 26 ])
      seed_room_type_options("Garden Prestige Suite", month: 5, days: [ 21, 22, 23, 24, 25, 26 ])

      post path, params: { message: "late may", phone: phone }.to_json, headers: headers
      post path, params: { message: "4 days 3 nights", phone: phone }.to_json, headers: headers
      post path, params: { message: "2 adults", phone: phone }.to_json, headers: headers
      post path, params: { message: "any hotel policies?", phone: phone }.to_json, headers: headers

      expect(parsed_body["reply_message"]).to include("Here is our hotel policy")

      post path, params: { message: "ok i want to book executive on may 22", phone: phone }.to_json, headers: headers

      expect(response).to have_http_status(:ok)
      expect(parsed_body["reply_message"]).to include("Executive Penthouse")
      expect(parsed_body["reply_message"]).to include("Please reply *Yes* to confirm the book and *No* to reconsider the choices.")
    end

    it "resumes the saved option set after a room information interruption" do
      room_type = seed_room_type_options("Executive Suite", month: 5, days: [ 21, 22, 23, 24, 25, 26 ])
      room_type.update!(
        description: "Large suite with sea view.",
        amenities: %w[wifi balcony]
      )

      post path, params: { message: "late may", phone: phone }.to_json, headers: headers
      post path, params: { message: "4 days 3 nights", phone: phone }.to_json, headers: headers
      post path, params: { message: "2 adults", phone: phone }.to_json, headers: headers
      post path, params: { message: "tell me about the executive suite", phone: phone }.to_json, headers: headers

      expect(parsed_body["reply_message"]).to include("Here are the details for Executive Suite")

      post path, params: { message: "ok i want executive suite on may 22", phone: phone }.to_json, headers: headers

      expect(response).to have_http_status(:ok)
      expect(parsed_body["reply_message"]).to include("Executive Suite")
      expect(parsed_body["reply_message"]).to include("Please reply *Yes* to confirm the book and *No* to reconsider the choices.")
    end

    it "selects the only visible option when the guest replies with just the room type name" do
      seed_room_type_options("Executive Penthouse", month: 6, days: [ 6, 7, 8, 9 ], max_adults: 3)
      seed_room_type_options("Garden Prestige Suite", month: 6, days: [ 6, 7, 8, 9 ], max_adults: 3)

      post path, params: { message: "hello, any booking for early june?", phone: phone }.to_json, headers: headers
      post path, params: { message: "5 days 4 nights", phone: phone }.to_json, headers: headers
      post path, params: { message: "3 adults 3 children", phone: phone }.to_json, headers: headers
      post path, params: { message: "can i chose executive penthouse", phone: phone }.to_json, headers: headers

      expect(response).to have_http_status(:ok)
      expect(parsed_body["reply_message"]).to include("Executive Penthouse")
      expect(parsed_body["reply_message"]).to include("Please reply *Yes* to confirm the book and *No* to reconsider the choices.")
    end

    it "selects an option when the guest says i chose option 1" do
      seed_room_type_options("Garden Prestige Suite", month: 8, days: [ 21, 22, 23 ])

      post path, params: { message: "hello, any booking for late august?", phone: phone }.to_json, headers: headers
      post path, params: { message: "2 days 1 night", phone: phone }.to_json, headers: headers
      post path, params: { message: "2 adults", phone: phone }.to_json, headers: headers
      post path, params: { message: "i chose option 1", phone: phone }.to_json, headers: headers

      expect(response).to have_http_status(:ok)
      expect(parsed_body["reply_message"]).to include("Garden Prestige Suite")
      expect(parsed_body["reply_message"]).to include("Please reply *Yes* to confirm the book and *No* to reconsider the choices.")
    end

    it "uses the pending date context to avoid looping after the guest names the room type" do
      seed_room_type_options("Ocean Villa King", month: 5, days: [ 21, 22, 23, 24, 25, 26 ])
      seed_room_type_options("Executive Penthouse", month: 5, days: [ 21, 22, 23, 24, 25, 26 ])
      seed_room_type_options("Garden Prestige Suite", month: 5, days: [ 21, 22, 23, 24, 25, 26 ])

      post path, params: { message: "hello, any booking for late may?", phone: phone }.to_json, headers: headers
      post path, params: { message: "4 days 3 nights", phone: phone }.to_json, headers: headers
      post path, params: { message: "2 adults", phone: phone }.to_json, headers: headers
      post path, params: { message: "may 21", phone: phone }.to_json, headers: headers
      expect(parsed_body["reply_message"]).to include("Please tell me which room type you want")

      post path, params: { message: "ocean villa king", phone: phone }.to_json, headers: headers

      expect(response).to have_http_status(:ok)
      expect(parsed_body["reply_message"]).to include("Ocean Villa King")
      expect(parsed_body["reply_message"]).to include("Please reply *Yes* to confirm the book and *No* to reconsider the choices.")
    end

    it "accepts a unique partial room type name after ambiguous date follow-up" do
      seed_room_type_options("Executive Penthouse", month: 5, days: [ 21, 22, 23, 24, 25 ])
      seed_room_type_options("Garden Prestige Suite", month: 5, days: [ 21, 22, 23, 24, 25 ])

      post path, params: { message: "hello, any booking for late may?", phone: phone }.to_json, headers: headers
      post path, params: { message: "4 days 3 nights", phone: phone }.to_json, headers: headers
      post path, params: { message: "2 adults", phone: phone }.to_json, headers: headers
      post path, params: { message: "may 21", phone: phone }.to_json, headers: headers
      expect(parsed_body["reply_message"]).to include("Please tell me which room type you want")

      post path, params: { message: "garden prestige suit", phone: phone }.to_json, headers: headers

      expect(response).to have_http_status(:ok)
      expect(parsed_body["reply_message"]).to include("Garden Prestige Suite")
      expect(parsed_body["reply_message"]).to include("Please reply *Yes* to confirm the book and *No* to reconsider the choices.")
    end

    it "treats executive one as room type shorthand and asks for the option number" do
      seed_room_type_options("Ocean Villa King", month: 7, days: [ 1, 2, 3, 4 ])
      seed_room_type_options("Executive Penthouse", month: 7, days: [ 1, 2, 3, 4 ])
      seed_room_type_options("Garden Prestige Suite", month: 7, days: [ 1, 2, 3, 4 ])

      post path, params: { message: "early july", phone: phone }.to_json, headers: headers
      post path, params: { message: "3 days 2 nights", phone: phone }.to_json, headers: headers
      post path, params: { message: "2 adults", phone: phone }.to_json, headers: headers
      post path, params: { message: "executive one", phone: phone }.to_json, headers: headers

      expect(response).to have_http_status(:ok)
      expect(parsed_body["reply_message"]).to include("Executive Penthouse")
      expect(parsed_body["reply_message"]).to include("I found multiple options under Executive Penthouse:")
      expect(parsed_body["reply_message"]).to include("1. *RM")
      expect(parsed_body["reply_message"]).to include("Please tell me the option number you want.")
    end

    it "returns a booking url with total and expiry after yes" do
      seed_room_type_options("Garden Prestige Suite", month: 8, days: [ 11, 12, 13, 14 ])

      post path, params: { message: "mid august", phone: phone }.to_json, headers: headers
      post path, params: { message: "3 days 2 nights", phone: phone }.to_json, headers: headers
      post path, params: { message: "2 adults", phone: phone }.to_json, headers: headers
      post path, params: { message: "Garden Prestige Suite option 2", phone: phone }.to_json, headers: headers
      post path, params: { message: "yes", phone: phone }.to_json, headers: headers

      expect(response).to have_http_status(:ok)
      expect(parsed_body["reply_message"]).to include("Quotation link:")
      expect(parsed_body["reply_message"]).to include("Total:")
      expect(parsed_body["reply_message"]).to include("will expire")
      expect(parsed_body["action_name"]).to be_nil
      state = Prospect.lookup_by_phone(phone).first.prospect_conversation_state
      expect(state.flow_status).to eq("ended")
      expect(state.slots_payload.dig("conversation", "end_reason")).to eq("booking_url_generated")
    end

    it "starts a fresh branch after another booking" do
      seed_room_type_options("Garden Prestige Suite", month: 8, days: [ 11, 12, 13, 14 ])

      post path, params: { message: "mid august", phone: phone }.to_json, headers: headers
      post path, params: { message: "3 days 2 nights", phone: phone }.to_json, headers: headers
      post path, params: { message: "2 adults", phone: phone }.to_json, headers: headers
      post path, params: { message: "Garden Prestige Suite option 2", phone: phone }.to_json, headers: headers
      post path, params: { message: "yes", phone: phone }.to_json, headers: headers

      expect(parsed_body["reply_message"]).to include("Quotation link:")

      post path, params: { message: "another booking", phone: phone }.to_json, headers: headers

      expect(response).to have_http_status(:ok)
      expect(parsed_body["reply_message"]).to include("what dates or month")
      expect(parsed_body["reply_message"]).not_to include("Quotation link:")
      expect(parsed_body["reply_message"]).not_to include("Please reply *Yes* to confirm the book")
      expect(parsed_body["action_name"]).to eq("request_quote")
    end

    it "answers hotel amenities after a completed booking without room fallback" do
      hotel.update!(amenities: [ Hotel::HOTEL_AMENITIES.first.fetch(:id) ])
      seed_room_type_options("Garden Prestige Suite", month: 8, days: [ 11, 12, 13, 14 ])

      post path, params: { message: "mid august", phone: phone }.to_json, headers: headers
      post path, params: { message: "3 days 2 nights", phone: phone }.to_json, headers: headers
      post path, params: { message: "2 adults", phone: phone }.to_json, headers: headers
      post path, params: { message: "Garden Prestige Suite option 2", phone: phone }.to_json, headers: headers
      post path, params: { message: "yes", phone: phone }.to_json, headers: headers

      expect(parsed_body["reply_message"]).to include("Quotation link:")

      post path, params: { message: "may i know hotel amenities", phone: phone }.to_json, headers: headers

      expect(response).to have_http_status(:ok)
      expect(parsed_body["reply_message"]).to include("Hotel amenities:")
      expect(parsed_body["reply_message"]).not_to include("I couldn't match that room type")
    end

    it "returns 422 when concierge is disabled" do
      hotel.update!(ai_provider_enabled: false)

      post path, params: { message: "Hello", phone: phone }.to_json, headers: headers

      expect(response).to have_http_status(:unprocessable_content)
      expect(parsed_body["error"]).to eq("AI Concierge is not enabled for this hotel.")
    end

    it "returns 422 when phone and prospect public id are missing" do
      post path, params: { message: "Hello" }.to_json, headers: headers

      expect(response).to have_http_status(:unprocessable_content)
      expect(parsed_body["error"]).to eq("Phone or prospect_public_id is required for AI concierge conversations")
    end

    it "continues a conversation by prospect public id" do
      post path, params: { message: "hello, any booking for early august?", phone: phone }.to_json, headers: headers
      prospect_public_id = parsed_body["prospect_public_id"]

      post path, params: { message: "3 days 2 nights", prospect_public_id: prospect_public_id }.to_json, headers: headers

      expect(response).to have_http_status(:ok)
      expect(parsed_body["prospect_public_id"]).to eq(prospect_public_id)
      expect(parsed_body["reply_message"]).to include("early August")
      expect(parsed_body["reply_message"]).to include("How many guests")
    end

    it "returns 404 for an invalid prospect public id" do
      post path, params: { message: "Hello", prospect_public_id: "prsp_missing" }.to_json, headers: headers

      expect(response).to have_http_status(:not_found)
      expect(parsed_body["error"]).to eq("Prospect not found")
    end

    it "ends and reactivates the same conversation state" do
      post path, params: { message: "Hello", phone: phone }.to_json, headers: headers
      prospect_public_id = parsed_body["prospect_public_id"]

      post path, params: { message: "stop", prospect_public_id: prospect_public_id }.to_json, headers: headers
      expect(response).to have_http_status(:ok)
      expect(parsed_body["reply_message"]).to eq("No problem, please let me know if you need anything.")

      state = Prospect.find_by!(public_id: prospect_public_id).prospect_conversation_state
      expect(state.flow_status).to eq("ended")
      expect(state.slots_payload.dig("conversation", "end_reason")).to eq("user_ended")

      post path, params: { message: "hello, any booking for early august?", prospect_public_id: prospect_public_id }.to_json, headers: headers

      state.reload
      expect(response).to have_http_status(:ok)
      expect(state.flow_status).not_to eq("ended")
      expect(state.slots_payload.dig("conversation", "status")).to eq("active")
      expect(state.slots_payload.dig("conversation", "end_reason")).to be_nil
    end
  end

  def stub_interpreter
    allow_any_instance_of(AiConciergeV3::Agents::InterpreterAgent).to receive(:call) do |agent|
      build_interpretation(
        message: agent.instance_variable_get(:@message),
        conversation_summary: agent.instance_variable_get(:@conversation_summary)
      )
    end
  end

  def build_interpretation(message:, conversation_summary:)
    normalized = message.to_s.downcase.strip

    if normalized.match?(/\bpolic(?:y|ies)\b/)
      return interpretation(intent: "hotel_policy", topic: "hotel_policy")
    end

    if normalized.match?(/\b(attractions?|nearby|places?)\b/)
      return interpretation(intent: "nearby_attractions", topic: "nearby_attractions")
    end

    if normalized.match?(/\bfaq\b/)
      return interpretation(intent: "hotel_information", topic: "hotel_faq")
    end

    if normalized.match?(/\b(amenit(?:y|ies)|facilit(?:y|ies))\b/) && normalized.match?(/\b(hotel|property)\b/)
      return interpretation(intent: "hotel_information", topic: "general_hotel_info")
    end

    if normalized.match?(/\b(tell me about|details for|about the)\b/) && normalized.match?(/\b(exec|executive|ocean|villa|suite|room)\b/)
      return interpretation(intent: "room_information", topic: "room_information", slots: { "room_type_name" => inferred_room_type_name(normalized) })
    end

    if normalized.include?("tell me about the hotel")
      return interpretation(intent: "hotel_information", topic: "general_hotel_info")
    end

    if normalized.include?("another booking")
      return interpretation(
        intent: "booking_search",
        topic: "booking_search",
        signals: { "starts_new_booking_branch" => true }
      )
    end

    if normalized.match?(/\b(option|suite|room)\b/) && normalized.match?(/\boption\s*\d+\b/)
      return interpretation(
        intent: "option_selection",
        topic: "booking_search",
        slots: { "option_number" => normalized[/\boption\s*(\d+)\b/, 1] }
      )
    end

    if normalized == "yes"
      return interpretation(intent: "confirmation", topic: "booking_search", slots: { "confirmation" => "yes" })
    end

    if normalized.include?("2 adults")
      if normalized.include?("hello, is there any booking")
        return interpretation(
          intent: "booking_search",
          topic: "booking_search",
          slots: month_slots(5, "early").merge("adults" => 2, "children" => 0)
        )
      end

      return interpretation(intent: "booking_search", topic: "booking_search", slots: { "adults" => 2, "children" => 0 })
    end

    if normalized.include?("2 people")
      if normalized.include?("early june")
        return interpretation(intent: "booking_search", topic: "booking_search", slots: month_slots(6, "early").merge("adults" => 2, "party_size_total" => 2))
      end

      return interpretation(intent: "booking_search", topic: "booking_search", slots: { "party_size_total" => 2 })
    end

    if normalized == "adults"
      return interpretation(intent: "booking_search", topic: "booking_search")
    end

    if normalized.include?("3 days 2 nights")
      return interpretation(intent: "booking_search", topic: "booking_search", slots: { "days" => 3, "nights" => 2 })
    end

    if normalized.include?("5 days 4 nights")
      return interpretation(intent: "booking_search", topic: "booking_search", slots: { "days" => 5, "nights" => 4 })
    end

    if normalized.include?("2 days 1 night")
      return interpretation(intent: "booking_search", topic: "booking_search", slots: { "days" => 2, "nights" => 1 })
    end

    if normalized.include?("4 days 3 nights")
      return interpretation(intent: "booking_search", topic: "booking_search", slots: { "days" => 4, "nights" => 3 })
    end

    if normalized.include?("3 adults 3 children")
      return interpretation(intent: "booking_search", topic: "booking_search", slots: { "adults" => 3, "children" => 3 })
    end

    if normalized.include?("early june")
      return interpretation(intent: "booking_search", topic: "booking_search", slots: month_slots(6, "early").merge("days" => 5, "nights" => 4))
    end

    if normalized.include?("early july")
      return interpretation(intent: "booking_search", topic: "booking_search", slots: month_slots(7, "early").merge("days" => 3, "nights" => 2, "adults" => 2, "children" => 0))
    end

    if normalized.include?("early august")
      return interpretation(intent: "booking_search", topic: "booking_search", slots: month_slots(8, "early").merge("days" => 3, "nights" => 2))
    end

    if normalized.include?("mid august")
      return interpretation(intent: "booking_search", topic: "booking_search", slots: month_slots(8, "mid").merge("days" => 3, "nights" => 2))
    end

    if normalized.include?("late august")
      return interpretation(intent: "booking_search", topic: "booking_search", slots: month_slots(8, "late").merge("days" => 2, "nights" => 1))
    end

    if normalized.include?("late may")
      return interpretation(intent: "booking_search", topic: "booking_search", slots: month_slots(5, "late").merge("days" => 4, "nights" => 3))
    end

    if normalized.match?(/may\s+\d+/)
      day = normalized[/may\s+(\d+)/, 1].to_i
      return interpretation(intent: "booking_search", topic: "booking_search", slots: { "check_in" => Date.new(infer_year(5), 5, day).iso8601 })
    end

    if normalized.match?(/august\s+\d+/)
      day = normalized[/august\s+(\d+)/, 1].to_i
      return interpretation(intent: "booking_search", topic: "booking_search", slots: { "check_in" => Date.new(infer_year(8), 8, day).iso8601 })
    end

    interpretation(intent: "greeting", topic: "general")
  end

  def interpretation(intent:, topic:, slots: {}, signals: {})
    {
      "intent" => intent,
      "topic" => topic,
      "confidence" => 1.0,
      "slots" => slots,
      "tool_hints" => [],
      "conversation_signals" => {
        "is_reset" => false,
        "is_resume" => false,
        "is_correction" => false,
        "starts_new_booking_branch" => false,
        "end_conversation" => false
      }.merge(signals)
    }
  end

  def month_slots(month, segment)
    {
      "target_month" => month,
      "target_year" => infer_year(month),
      "month_segment" => segment
    }
  end

  def seed_room_type_options(room_type_name, month:, days:, max_adults: 2)
    year = infer_year(month)
    room_type = create(:room_type, hotel: hotel, name: room_type_name, base_price: 180, max_adults: max_adults)

    days.each_with_index do |day, index|
      date = Date.new(year, month, day)
      create(:room_rate, room_type: room_type, date: date, price: 220 + index, currency: "MYR")
      create(:room_inventory, room_type: room_type, date: date, quantity: 2, status: "open")
    end

    room_type
  end

  def infer_year(month)
    candidate = Date.new(Date.current.year, month, 1)
    candidate < Date.current.beginning_of_month ? Date.current.year + 1 : Date.current.year
  end

  def parsed_body
    JSON.parse(response.body)
  end

  def inferred_room_type_name(normalized)
    return "Executive Suite" if normalized.include?("exec") || normalized.include?("executive")
    return "Ocean Villa" if normalized.include?("ocean villa")

    nil
  end
end
