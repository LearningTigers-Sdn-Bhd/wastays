require "rails_helper"

RSpec.describe "API V1 AI Concierge Inquiries", type: :request do
  let(:hotel) { create(:hotel, :with_ai_concierge) }
  let(:api_key) { create(:api_key, bearer: hotel) }
  let(:headers) { { "Authorization" => "Bearer #{api_key.token}", "Content-Type" => "application/json" } }
  let(:path) { "/api/v1/hotels/#{hotel.id}/ai_concierge/inquiries" }
  let(:phone) { "0123456789" }

  before do
    create(:property_policy, hotel: hotel, check_in_time: "15:00", check_out_time: "12:00", cancellation_policy: "24 hours")
    create(:guest, phone: "+60123456789")
    stub_interpreter
  end

  describe "POST /api/v1/hotels/:hotel_id/ai_concierge/inquiries" do
    it "answers hotel policy questions" do
      post path, params: { message: "What is the policy of this hotel?" }.to_json, headers: headers

      expect(response).to have_http_status(:ok)
      expect(parsed_body).to eq(
        "reply_message" => [
          "Welcome to #{hotel.name}! Here is our hotel policy:",
          "- Check-in starts at: *15:00*",
          "- Check-out is at: *12:00*",
          "- Cancellation: *24 hours*"
        ].join("\n"),
        "needs_human_support" => false,
        "action_name" => nil
      )
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
      expect(parsed_body["reply_message"]).to include("What dates or month")
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
      expect(parsed_body["reply_message"]).to include("1. RM")
      expect(parsed_body["reply_message"]).to include("Check-in *August 1* - Check-out *August 3*")
      expect(parsed_body["reply_message"]).to include('Reply with the room type name and option number or date you want, for example: "Ocean Villa King option 1" or "Executive Penthouse on May 21".')
    end

    it "selects a unique shown option by date text" do
      seed_room_type_options("Garden Prestige Suite", month: 8, days: [ 1, 2, 3, 4 ])

      post path, params: { message: "hello, any booking for early august?", phone: phone }.to_json, headers: headers
      post path, params: { message: "3 days 2 nights", phone: phone }.to_json, headers: headers
      post path, params: { message: "2 adults", phone: phone }.to_json, headers: headers
      post path, params: { message: "August 3rd", phone: phone }.to_json, headers: headers

      expect(response).to have_http_status(:ok)
      expect(parsed_body["reply_message"]).to include("Garden Prestige Suite")
      expect(parsed_body["reply_message"]).to include("Please reply *Yes* or *No*.")
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
      expect(parsed_body["reply_message"]).to include("Please reply *Yes* or *No*.")
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
      expect(parsed_body["reply_message"]).to include("Please reply *Yes* or *No*.")
    end

    it "selects an option when the guest says i chose option 1" do
      seed_room_type_options("Garden Prestige Suite", month: 8, days: [ 21, 22, 23 ])

      post path, params: { message: "hello, any booking for late august?", phone: phone }.to_json, headers: headers
      post path, params: { message: "2 days 1 night", phone: phone }.to_json, headers: headers
      post path, params: { message: "2 adults", phone: phone }.to_json, headers: headers
      post path, params: { message: "i chose option 1", phone: phone }.to_json, headers: headers

      expect(response).to have_http_status(:ok)
      expect(parsed_body["reply_message"]).to include("Garden Prestige Suite")
      expect(parsed_body["reply_message"]).to include("Please reply *Yes* or *No*.")
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
      expect(parsed_body["reply_message"]).to include("Please reply *Yes* or *No*.")
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
      expect(parsed_body["reply_message"]).to include("Please reply *Yes* or *No*.")
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
      expect(parsed_body["reply_message"]).to include("1. RM")
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
      expect(parsed_body["reply_message"]).to include("Book here:")
      expect(parsed_body["reply_message"]).to include("Total:")
      expect(parsed_body["reply_message"]).to include("expires")
      expect(parsed_body["action_name"]).to be_nil
    end

    it "starts a fresh branch after another booking" do
      seed_room_type_options("Garden Prestige Suite", month: 8, days: [ 11, 12, 13, 14 ])

      post path, params: { message: "mid august", phone: phone }.to_json, headers: headers
      post path, params: { message: "3 days 2 nights", phone: phone }.to_json, headers: headers
      post path, params: { message: "2 adults", phone: phone }.to_json, headers: headers
      post path, params: { message: "Garden Prestige Suite option 2", phone: phone }.to_json, headers: headers
      post path, params: { message: "yes", phone: phone }.to_json, headers: headers

      expect(parsed_body["reply_message"]).to include("Book here:")

      post path, params: { message: "another booking", phone: phone }.to_json, headers: headers

      expect(response).to have_http_status(:ok)
      expect(parsed_body["reply_message"]).to include("What dates or month")
      expect(parsed_body["reply_message"]).not_to include("Book here:")
      expect(parsed_body["reply_message"]).not_to include("Please reply *Yes* or *No*.")
      expect(parsed_body["action_name"]).to eq("request_quote")
    end

    it "returns 422 when concierge is disabled" do
      hotel.update!(ai_provider_enabled: false)

      post path, params: { message: "Hello" }.to_json, headers: headers

      expect(response).to have_http_status(:unprocessable_content)
      expect(parsed_body["error"]).to eq("AI Concierge is not enabled for this hotel.")
    end
  end

  def stub_interpreter
    allow_any_instance_of(AiConciergeV3::InterpreterAgent).to receive(:call) do |agent|
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
        "starts_new_booking_branch" => false
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
  end

  def infer_year(month)
    candidate = Date.new(Date.current.year, month, 1)
    candidate < Date.current.beginning_of_month ? Date.current.year + 1 : Date.current.year
  end

  def parsed_body
    JSON.parse(response.body)
  end
end
