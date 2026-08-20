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
    stub_concierge_conversation
  end

  # The ordinal counts the list as the guest reads it, and the list opens with
  # the cheapest plan -- so "first one" is the Non-Refundable Rate here.
  it "selects the first rate plan by ordinal language" do
    _standard, non_refundable = seed_rate_plan_options

    run_to_rate_plan_prompt
    post_message("first one")

    expect(parsed_body["reply_message"]).to include("(Non-Refundable Rate)")
    expect(active_branch["selected_rate_plan_id"]).to eq(non_refundable.id)
    expect(active_branch["selected_rate_plan_name"]).to eq("Non-Refundable Rate")
  end

  # The list opens with the cheapest plan, so the cheapest is row 1.
  it "selects a rate plan by its row number" do
    _standard, non_refundable = seed_rate_plan_options(standard_price: 260, non_refundable_price: 210)

    run_to_rate_plan_prompt
    post_message("no 1")

    expect(parsed_body["reply_message"]).to include("(Non-Refundable Rate)")
    expect(active_branch["selected_rate_plan_id"]).to eq(non_refundable.id)
  end

  it "resumes suspended booking after a hotel info interruption and selects the cheaper plan" do
    _standard, non_refundable = seed_rate_plan_options(standard_price: 260, non_refundable_price: 210)

    run_to_rate_plan_prompt
    post_message("what time is check in?")

    expect(parsed_body["reply_message"]).to include("Check-in starts")

    post_message("no 1")

    expect(parsed_body["reply_message"]).to include("(Non-Refundable Rate)")
    expect(active_branch["selected_rate_plan_id"]).to eq(non_refundable.id)
  end

  it "does not choose the row above the one the guest numbered" do
    refundable, non_refundable = seed_rate_plan_options(
      standard_name: "Refundable Rate",
      standard_price: 260,
      non_refundable_price: 210
    )

    run_to_rate_plan_prompt
    post_message("no 2")

    expect(active_branch["selected_rate_plan_id"]).to eq(refundable.id)
    expect(active_branch["selected_rate_plan_id"]).not_to eq(non_refundable.id)
    expect(parsed_body["reply_message"]).to include("(Refundable Rate)")
  end

  # A rate plan's name is not a way into the list any more.
  it "re-asks when the guest names a plan instead of numbering a row" do
    seed_rate_plan_options(standard_name: "Standard Rate", non_refundable_name: "Standard Flexible Rate")

    run_to_rate_plan_prompt
    post_message("standard")

    expect(parsed_body["reply_message"]).to include("Which rate would you like?")
    expect(active_branch["selected_rate_plan_id"]).to be_nil
    expect(active_branch["confirmation_candidate"]).to be_nil
  end

  it "keeps the selected rate plan in the confirmation candidate" do
    _standard, non_refundable = seed_rate_plan_options(standard_price: 260, non_refundable_price: 210)

    run_to_rate_plan_prompt
    post_message("no 1")

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

  it "changes rate after confirmation candidate, selects a cheaper rate, and confirms a quote" do
    _standard, non_refundable = seed_rate_plan_options(standard_price: 260, non_refundable_price: 210)

    run_to_rate_plan_prompt
    post_message("second one")
    expect(active_branch["selected_rate_plan_name"]).to eq("Standard Rate")

    post_message("change rate")
    expect(parsed_body["reply_message"]).to include("Which rate would you like?")
    expect(active_branch["selected_rate_plan_id"]).to be_nil
    expect(active_branch["confirmation_candidate"]).to be_nil

    post_message("no 1")
    expect(active_branch["selected_rate_plan_id"]).to eq(non_refundable.id)

    post_message("yes")
    expect(parsed_body["reply_message"]).to include("Quotation link:")
    expect(parsed_body["reply_message"]).to include("Total:")
    expect(Prospect.lookup_by_phone(phone).first.prospect_conversation_state.reload.flow_status).to eq("ended")
  end

  it "changes room after a hotel info interruption and asks for rates on the new room" do
    seed_rate_plan_options
    deluxe_standard, _deluxe_flexible = seed_rate_plan_options(
      room_name: "Deluxe Room",
      standard_price: 260,
      non_refundable_name: "Flexible Rate",
      non_refundable_price: 290
    )

    run_to_rate_plan_prompt
    post_message("first one")
    post_message("what time is check in?")
    expect(parsed_body["reply_message"]).to include("Check-in starts")

    # Option 4 rather than 1: the catalogue numbers every room in one run, and
    # Deluxe Room's own rows start after Garden Prestige Suite's.
    post_message("change room to Deluxe Room option 4")
    expect(parsed_body["reply_message"]).to include("*Deluxe Room*")
    expect(parsed_body["reply_message"]).to include("Which rate would you like?")
    expect(active_branch["selected_option"]["room_type_name"]).to eq("Deluxe Room")
    expect(active_branch["selected_rate_plan_id"]).to be_nil

    post_message("first one")
    expect(active_branch["selected_rate_plan_id"]).to eq(deluxe_standard.id)
    expect(parsed_body["reply_message"]).to include("Deluxe Room")
    expect(parsed_body["reply_message"]).to include("(Standard Rate)")
  end

  # A live thread: "no 2" came back from the model as two nights, the changed
  # search discarded the chosen room, and the rate question was rendered with
  # no room name, no dates and no rates in it.
  it "picks the second rate from no 2, without losing the room" do
    _standard, non_refundable = seed_rate_plan_options

    run_to_rate_plan_prompt
    post_message("no 2")

    expect(parsed_body["reply_message"]).to include(room_name)
    expect(parsed_body["reply_message"]).to include("(Standard Rate)")
    expect(active_branch["selected_rate_plan_name"]).to eq("Standard Rate")
    expect(active_branch["selected_rate_plan_id"]).not_to eq(non_refundable.id)
  end

  # The rate question is written from the chosen option, so once a real slot
  # change clears it there is nothing left to ask about. The catalogue is the
  # honest answer, not a question with the room left blank.
  it "re-lists the options when a slot change clears the room mid rate question" do
    seed_rate_plan_options

    run_to_rate_plan_prompt
    post_message("actually 3 rooms")

    expect(parsed_body["reply_message"]).not_to include("Which rate would you like?")
    expect(parsed_body["reply_message"]).to match(/Here are the available options|couldn't find any rooms/)
  end

  # A live thread: the model answered "yes" with an advance_booking call that
  # carried no confirmation, so the confirmed room was never quoted -- the
  # guest was shown the catalogue again instead.
  it "quotes the confirmed room when the model sends a yes with no confirmation slot" do
    seed_rate_plan_options
    stub_concierge_model(
      room_type_names: [ room_name ],
      scripted: {
        "yes" => { tool: "advance_booking", arguments: { "slots" => {} } }
      }
    )

    run_to_rate_plan_prompt
    post_message("second one")
    post_message("yes")

    expect(parsed_body["reply_message"]).to include("Quotation link:")
    expect(parsed_body["reply_message"]).not_to include("Here are the available options")
  end

  # Picking a room is not picking a rate. "no 1" chose the first room and the
  # first rate plan with it, so the guest was shown a price -- the dearer one,
  # on a catalogue built before the plans were sorted -- that nobody had asked
  # them about.
  it "asks which rate after a row is picked, whatever words the row was picked in" do
    seed_rate_plan_options

    [ "no 1", "1", "the first one", "1st" ].each_with_index do |answer, index|
      @phone = "01288800#{index}0"
      post_message("mid august")
      post_message("3 days 2 nights")
      post_message("2 adults")
      post_message(answer)

      expect(parsed_body["reply_message"]).to include("Which rate would you like?"), "expected #{answer.inspect} to reach the rate question"
      expect(parsed_body["reply_message"]).not_to include("Please reply *Yes* to confirm")
    end
  end

  # The same turn, with the model volunteering a rate plan the guest never
  # mentioned. On a message that names nothing but a row it can only have
  # invented one, and inventing the dearer one is how a guest ends up looking
  # at a price they were never offered.
  it "ignores a rate plan the model supplies on a turn that only picks a row" do
    seed_rate_plan_options(standard_price: 260, non_refundable_price: 210)
    stub_concierge_model(
      room_type_names: [ room_name ],
      scripted: {
        "no 1" => { tool: "advance_booking", arguments: { "slots" => { "rate_plan_name" => "Standard Rate" } } }
      }
    )

    post_message("mid august")
    post_message("3 days 2 nights")
    post_message("2 adults")
    post_message("no 1")

    expect(parsed_body["reply_message"]).to include("Which rate would you like?")
    expect(active_branch["selected_rate_plan_name"]).to be_nil
  end

  it "still cancels the booking attempt from natural abandonment language" do
    seed_rate_plan_options

    run_to_rate_plan_prompt
    post_message("first one")
    post_message("changed my mind")

    expect(parsed_body["reply_message"]).to include("I've cancelled your booking attempt")
    expect(active_branch["selected_option"]).to be_nil
    expect(active_branch["confirmation_candidate"]).to be_nil
  end

  it "returns to option selection when the guest rejects confirmation" do
    seed_rate_plan_options

    run_to_rate_plan_prompt
    post_message("first one")
    post_message("no")

    expect(parsed_body["reply_message"]).to include("Here are the available options")
    expect(active_branch["confirmation_candidate"]).to be_nil
    expect(Prospect.lookup_by_phone(phone).first.prospect_conversation_state.reload.pending_question).to eq("select_option")
  end

  # The reader this replaced only understood first, second and third.
  it "reaches a rate plan past the third row" do
    seed_rate_plan_options
    room_type = hotel.room_types.find_by(name: room_name)
    third = create(:rate_plan, room_type: room_type, name: "Long Stay Rate")
    [ 11, 12, 13, 14 ].each do |day|
      create(:room_rate, room_type: room_type, rate_plan: third, date: Date.new(infer_year(8), 8, day), price: 300, currency: "MYR")
    end

    run_to_rate_plan_prompt
    post_message("option 3")

    expect(parsed_body["reply_message"]).to include("(Long Stay Rate)")
    expect(active_branch["selected_rate_plan_id"]).to eq(third.id)
  end

  def seed_rate_plan_options(room_name: self.room_name, standard_name: "Standard Rate", non_refundable_name: "Non-Refundable Rate", standard_price: 240, non_refundable_price: 220)
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

    expect(parsed_body["reply_message"]).to include("Which rate would you like?")
  end

  def post_message(message)
    post path, params: { message: message, phone: @phone || phone }.to_json, headers: headers
  end

  def active_branch
    prospect = Prospect.lookup_by_phone(phone).first
    prospect.prospect_conversation_state.reload.slots_payload.dig("booking_task", "branch")
  end

  # ReferenceClassifier reads every message here except the rate-plan choices:
  # picking a plan by price or by ordinal is not slot extraction from the
  # sentence, it is the model naming one of the options it was just shown.
  def stub_concierge_conversation
    stub_concierge_model(
      room_type_names: [ room_name, "Deluxe Room" ],
      scripted: {
        "first one" => rate_plan_choice("first one"),
        "cheapest" => rate_plan_choice("cheapest"),
        "refundable" => rate_plan_choice("refundable"),
        "standard" => rate_plan_choice("standard"),
        "no 1" => row_choice,
        "no 2" => row_choice,
        "option 3" => row_choice,
        "early september" => {
          tool: "advance_booking",
          arguments: {
            "slots" => month_slots(9, "early"),
            "signals" => { "is_correction" => true }
          }
        }
      }
    )
  end

  def rate_plan_choice(name)
    { tool: "advance_booking", arguments: { "slots" => { "rate_plan_name" => name }, "signals" => {} } }
  end

  # A row and nothing else: there is no slot in it for the model to fill.
  def row_choice
    { tool: "advance_booking", arguments: { "slots" => {}, "signals" => {} } }
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
