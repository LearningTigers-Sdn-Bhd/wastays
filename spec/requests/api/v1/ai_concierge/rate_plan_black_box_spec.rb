# frozen_string_literal: true

require "rails_helper"

RSpec.describe "AI Concierge rate-plan conversation coverage", type: :request do
  let(:hotel) { create(:hotel, :with_ai_concierge) }
  let(:api_key) { create(:api_key, bearer: hotel) }
  let(:headers) { { "Authorization" => "Bearer #{api_key.token}", "Content-Type" => "application/json" } }
  let(:path) { "/api/v1/hotels/#{hotel.id}/ai_concierge/inquiries" }
  let(:phone) { "+6012#{SecureRandom.random_number(10_000_000).to_s.rjust(7, '0')}" }
  let(:room_name) { "Garden Prestige Suite" }

  before do
    create(:property_policy, hotel: hotel, check_in_time: "15:00", check_out_time: "12:00", cancellation_policy: "24 hours")
    allow_any_instance_of(HotelKnowledges::SearchService).to receive(:call).and_return([])
    stub_interpreter
  end

  it "selects the first rate plan by ordinal language" do
    standard, _non_refundable = seed_rate_plan_options

    run_to_rate_plan_prompt
    post_message("first one")

    expect(parsed_body["reply_message"]).to include("(Standard Rate)")
    expect(active_branch["selected_rate_plan_id"]).to eq(standard.id)
    expect(active_branch["selected_rate_plan_name"]).to eq("Standard Rate")
  end

  it "selects the unique cheapest rate plan by price intent" do
    _standard, non_refundable = seed_rate_plan_options(standard_price: 260, non_refundable_price: 210)

    run_to_rate_plan_prompt
    post_message("cheapest")

    expect(parsed_body["reply_message"]).to include("(Non-Refundable Rate)")
    expect(active_branch["selected_rate_plan_id"]).to eq(non_refundable.id)
  end

  it "resumes suspended booking after a hotel info interruption and selects the cheaper plan" do
    _standard, non_refundable = seed_rate_plan_options(standard_price: 260, non_refundable_price: 210)

    run_to_rate_plan_prompt
    post_message("what time is check in?")

    expect(parsed_body["reply_message"]).to include("Check-in starts")

    post_message("the cheaper one")

    expect(parsed_body["reply_message"]).to include("(Non-Refundable Rate)")
    expect(active_branch["selected_rate_plan_id"]).to eq(non_refundable.id)
  end

  it "does not choose Non-Refundable Rate when the guest asks for refundable" do
    refundable, non_refundable = seed_rate_plan_options(
      standard_name: "Refundable Rate",
      standard_price: 260,
      non_refundable_price: 210
    )

    run_to_rate_plan_prompt
    post_message("refundable")

    expect(active_branch["selected_rate_plan_id"]).to eq(refundable.id)
    expect(active_branch["selected_rate_plan_id"]).not_to eq(non_refundable.id)
    expect(parsed_body["reply_message"]).to include("(Refundable Rate)")
  end

  it "re-asks when standard matches multiple rate plans" do
    seed_rate_plan_options(standard_name: "Standard Rate", non_refundable_name: "Standard Flexible Rate")

    run_to_rate_plan_prompt
    post_message("standard")

    expect(parsed_body["reply_message"]).to include("which rate plan would you like?")
    expect(active_branch["selected_rate_plan_id"]).to be_nil
    expect(active_branch["confirmation_candidate"]).to be_nil
  end

  it "keeps the selected rate plan in the confirmation candidate" do
    _standard, non_refundable = seed_rate_plan_options(standard_price: 260, non_refundable_price: 210)

    run_to_rate_plan_prompt
    post_message("cheapest")

    expect(parsed_body["reply_message"]).to include("Please reply *Yes* to confirm")
    expect(active_branch.dig("selected_option", "selected_rate_plan", "rate_plan_id")).to eq(non_refundable.id)
    expect(active_branch.dig("confirmation_candidate", "selected_rate_plan", "rate_plan_id")).to eq(non_refundable.id)
  end

  it "clears selected rate plan state after date correction" do
    seed_rate_plan_options

    run_to_rate_plan_prompt
    post_message("first one")
    expect(active_branch["selected_rate_plan_id"]).to be_present

    post_message("early september")

    expect(active_branch["selected_rate_plan_id"]).to be_nil
    expect(active_branch["selected_rate_plan_name"]).to be_nil
    expect(active_branch["selected_option"]).to be_nil
    expect(active_branch["confirmation_candidate"]).to be_nil
  end

  def seed_rate_plan_options(standard_name: "Standard Rate", non_refundable_name: "Non-Refundable Rate", standard_price: 240, non_refundable_price: 220)
    room_type = create(:room_type, hotel: hotel, name: room_name, base_price: standard_price, max_adults: 3)
    standard = create(:rate_plan, room_type: room_type, name: standard_name)
    non_refundable = create(:rate_plan, room_type: room_type, name: non_refundable_name)

    [ 11, 12, 13, 14 ].each do |day|
      date = Date.new(infer_year(8), 8, day)
      create(:room_inventory, room_type: room_type, date: date, quantity: 2, status: "open")
      create(:room_rate, room_type: room_type, rate_plan: standard, date: date, price: standard_price, currency: "MYR")
      create(:room_rate, room_type: room_type, rate_plan: non_refundable, date: date, price: non_refundable_price, currency: "MYR")
    end

    [ standard, non_refundable ]
  end

  def run_to_rate_plan_prompt
    post_message("mid august")
    post_message("3 days 2 nights")
    post_message("2 adults")
    post_message("#{room_name} option 1")

    expect(parsed_body["reply_message"]).to include("which rate plan would you like?")
  end

  def post_message(message)
    post path, params: { message: message, phone: phone }.to_json, headers: headers
  end

  def active_branch
    prospect = Prospect.lookup_by_phone(phone).first
    prospect.prospect_conversation_state.reload.slots_payload.dig("booking_task", "branch")
  end

  def stub_interpreter
    allow_any_instance_of(AiConciergeV3::Agents::InterpreterAgent).to receive(:call) do |agent|
      build_interpretation(agent.instance_variable_get(:@message))
    end
  end

  def build_interpretation(message)
    normalized = message.to_s.downcase.strip

    return interpretation(intent: "hotel_policy", topic: "hotel_policy") if normalized.include?("check in")
    return interpretation(slots: month_slots(8, "mid").merge("days" => 3, "nights" => 2)) if normalized.include?("mid august")
    return interpretation(slots: { "days" => 3, "nights" => 2 }) if normalized.include?("3 days 2 nights")
    return interpretation(slots: { "adults" => 2, "children" => 0 }) if normalized.include?("2 adults")
    return interpretation(slots: month_slots(9, "early"), signals: { "is_correction" => true }) if normalized.include?("early september")

    if normalized.match?(/\boption\s*\d+\b/)
      return interpretation(
        intent: "option_selection",
        slots: { "option_number" => normalized[/\boption\s*(\d+)\b/, 1] }
      )
    end

    if normalized.include?("the cheaper one")
      return interpretation(intent: "option_selection", slots: { "rate_plan_name" => "Non-Refundable Rate" })
    end

    if normalized.match?(/\b(first|cheapest|refundable|standard)\b/)
      return interpretation(intent: "option_selection", slots: { "rate_plan_name" => normalized })
    end

    interpretation(intent: "greeting", topic: "general")
  end

  def interpretation(intent: "booking_search", topic: "booking_search", slots: {}, signals: {})
    {
      "message_type" => "booking_request",
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

  def infer_year(month)
    candidate = Date.new(Date.current.year, month, 1)
    candidate < Date.current.beginning_of_month ? Date.current.year + 1 : Date.current.year
  end

  def parsed_body
    JSON.parse(response.body)
  end
end
