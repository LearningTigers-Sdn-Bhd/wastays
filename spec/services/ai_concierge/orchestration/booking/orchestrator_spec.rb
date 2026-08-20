require "rails_helper"

RSpec.describe AiConcierge::Orchestration::Booking::Orchestrator do
  let(:hotel) { create(:hotel, :with_ai_concierge) }
  let(:prospect) { create(:prospect, hotel: hotel, phone_number: "+60123456789") }
  let(:conversation_state) { create(:prospect_conversation_state, prospect: prospect, pending_question: pending_question, slots_payload: slots_payload) }
  let(:pending_question) { "select_option" }
  let(:slots_payload) do
    AiConcierge::State::ConversationTaskManager.new(slots_payload: {}).activate_booking(default_active_branch, pending_question: pending_question)
  end
  let(:decision) { { action: :booking, pending_question: pending_question } }
  let(:tool_registry) { instance_double(AiConcierge::Tools::ToolRegistry) }

  before do
    allow(tool_registry).to receive(:fetch).with("select_booking_option").and_return(AiConcierge::Tools::Booking::SelectBookingOptionTool)
  end

  # A list with one row on it has only one answer, whatever words arrive.
  it "selects the only visible option whatever the guest replies with" do
    result = orchestrate(
      message: "can i choose executive penthouse",
      interpretation: interpretation,
      active_branch: branch_with_options([
        group("Executive Penthouse", [ option(1, "exec_1", "2026-06-06") ])
      ])
    )

    expect(result[:reply_type]).to eq(:ask_confirmation)
    expect(result[:pending_question]).to eq("confirm_selection")
    expect(result.dig(:extra_context, :selected_option, "selection_id")).to eq("exec_1")
    expect(result.dig(:slots_payload, "booking_task", "branch", "selected_option", "selection_id")).to eq("exec_1")
  end

  it "selects the row the guest numbered, across room types" do
    result = orchestrate(
      message: "no 3",
      interpretation: interpretation(intent: "option_selection", slots: { "option_number" => 3 }),
      active_branch: branch_with_options([
        group("Garden Prestige Suite", [ option(1, "garden_1", "2026-08-01"), option(2, "garden_2", "2026-08-02") ]),
        group("Deluxe Room", [ option(3, "deluxe_1", "2026-08-01") ])
      ])
    )

    expect(result[:reply_type]).to eq(:ask_confirmation)
    expect(result.dig(:extra_context, :selected_option, "selection_id")).to eq("deluxe_1")
  end

  # The catalogue is answered by number. A room name or a date is not a second
  # way in, so the guest is asked again rather than sent a room they did not
  # pick.
  it "asks for the number again when the reply names a room or a date" do
    [ "garden prestige suite", "august 1" ].each do |message|
      result = orchestrate(
        message: message,
        interpretation: interpretation(intent: "option_selection", slots: {}),
        active_branch: branch_with_options([
          group("Garden Prestige Suite", [ option(1, "garden_1", "2026-08-01"), option(2, "garden_2", "2026-08-02") ]),
          group("Deluxe Room", [ option(3, "deluxe_1", "2026-08-01") ])
        ])
      )

      expect(result[:reply_type]).to eq(:invalid_selection), "expected #{message.inspect} not to select"
      expect(result[:pending_question]).to eq("select_option")
    end
  end

  it "keeps a failed quote on the thread so the guest can answer again" do
      failure_tool = Class.new do
        def initialize(hotel:, selected_option:, guest_phone:, rate_plan_id: nil); end

      def call
        { "success" => false, "error" => "Unable to generate quote right now." }
      end
    end

    allow(tool_registry).to receive(:fetch).with("generate_booking_url").and_return(failure_tool)

    selected_option = option(1, "garden_1", "2026-08-01")
    active_branch = branch_with_options([ group("Garden Prestige Suite", [ selected_option ]) ]).merge(
      "selected_option" => selected_option,
      "confirmation_candidate" => selected_option
    )
    result = orchestrate(
      message: "yes",
      interpretation: interpretation(intent: "confirmation", slots: { "confirmation" => "yes" }),
      active_branch: active_branch,
      decision: { action: :booking, pending_question: "confirm_selection" }
    )

    expect(result.dig(:extra_context, :message)).to eq("Unable to generate quote right now.")
    expect(result[:needs_human_support]).to be(true)
    expect(result[:pending_question]).to eq("confirm_selection")
    expect(result.slots_payload).to be_present
    expect(result.flow_status).to be_nil
    expect(result.end_reason).to be_nil
  end

  it "selects the rate plan the guest numbered" do
    selected_option = option(1, "garden_1", "2026-08-01").merge(
      "rate_plans" => [
        { "rate_plan_id" => 10, "name" => "Standard Rate", "total_price" => 240.0, "currency" => "MYR" },
        { "rate_plan_id" => 11, "name" => "Non-Refundable Rate", "total_price" => 210.0, "currency" => "MYR" }
      ]
    )
    active_branch = branch_with_options([ group("Garden Prestige Suite", [ selected_option ]) ]).merge("selected_option" => selected_option)

    result = orchestrate(
      message: "no 2",
      interpretation: interpretation(slots: {}),
      active_branch: active_branch,
      decision: { action: :booking, pending_question: "rate_plan_selection" }
    )

    expect(result[:reply_type]).to eq(:ask_confirmation)
    expect(result.dig(:extra_context, :selected_option, "selected_rate_plan", "name")).to eq("Non-Refundable Rate")
    expect(result.dig(:slots_payload, "booking_task", "branch", "selected_rate_plan_id")).to eq(11)
  end

  it "selects a rate plan by ordinal follow-up" do
    selected_option = option(1, "garden_1", "2026-08-01").merge(
      "rate_plans" => [
        { "rate_plan_id" => 10, "name" => "Standard Rate", "total_price" => 240.0, "currency" => "MYR" },
        { "rate_plan_id" => 11, "name" => "Flexible Rate", "total_price" => 260.0, "currency" => "MYR" }
      ]
    )
    active_branch = branch_with_options([ group("Garden Prestige Suite", [ selected_option ]) ]).merge("selected_option" => selected_option)

    result = orchestrate(
      message: "second one",
      interpretation: interpretation(slots: {}),
      active_branch: active_branch,
      decision: { action: :booking, pending_question: "rate_plan_selection" }
    )

    expect(result[:reply_type]).to eq(:ask_confirmation)
    expect(result.dig(:extra_context, :selected_option, "selected_rate_plan", "name")).to eq("Flexible Rate")
  end

  # A rate plan's name is no longer a way in either: it only ever guessed, and
  # a guess here prices a stay the guest never asked about.
  it "re-asks the rate question when the reply names a plan instead of a row" do
    selected_option = option(1, "garden_1", "2026-08-01").merge(
      "rate_plans" => [
        { "rate_plan_id" => 10, "name" => "Refundable Rate", "total_price" => 260.0, "currency" => "MYR" },
        { "rate_plan_id" => 11, "name" => "Non-Refundable Rate", "total_price" => 220.0, "currency" => "MYR" }
      ]
    )
    active_branch = branch_with_options([ group("Garden Prestige Suite", [ selected_option ]) ]).merge("selected_option" => selected_option)

    [ "refundable", "non refundable", "the cheapest one please" ].each do |message|
      result = orchestrate(
        message: message,
        interpretation: interpretation(slots: {}),
        active_branch: active_branch.deep_dup,
        decision: { action: :booking, pending_question: "rate_plan_selection" }
      )

      expect(result[:reply_type]).to eq(:ask_rate_plan), "expected #{message.inspect} to re-ask"
    end
  end

  it "re-asks for rate plan when a partial provider name is ambiguous" do
    selected_option = option(1, "garden_1", "2026-08-01").merge(
      "rate_plans" => [
        { "rate_plan_id" => 10, "name" => "Standard Rate", "total_price" => 240.0, "currency" => "MYR" },
        { "rate_plan_id" => 11, "name" => "Standard Flexible Rate", "total_price" => 260.0, "currency" => "MYR" }
      ]
    )
    active_branch = branch_with_options([ group("Garden Prestige Suite", [ selected_option ]) ]).merge("selected_option" => selected_option)

    result = orchestrate(
      message: "standard",
      interpretation: interpretation(slots: { "rate_plan_name" => "standard" }),
      active_branch: active_branch,
      decision: { action: :booking, pending_question: "rate_plan_selection" }
    )

    expect(result[:reply_type]).to eq(:ask_rate_plan)
    expect(result[:pending_question]).to eq("rate_plan_selection")
    expect(result.dig(:slots_payload, "booking_task", "branch", "confirmation_candidate")).to be_nil
  end

  it "asks for rate plan again when a booking-ready guest changes rates" do
    selected_option = option(1, "garden_1", "2026-08-01").merge(
      "rate_plans" => [
        { "rate_plan_id" => 10, "name" => "Standard Rate", "total_price" => 240.0, "currency" => "MYR" },
        { "rate_plan_id" => 11, "name" => "Non-Refundable Rate", "total_price" => 210.0, "currency" => "MYR" }
      ],
      "selected_rate_plan" => { "rate_plan_id" => 10, "name" => "Standard Rate", "total_price" => 240.0, "currency" => "MYR" }
    )
    active_branch = branch_with_options([ group("Garden Prestige Suite", [ selected_option ]) ]).merge(
      "selected_option" => selected_option,
      "confirmation_candidate" => selected_option,
      "selected_rate_plan_id" => 10,
      "selected_rate_plan_name" => "Standard Rate"
    )

    result = orchestrate(
      message: "show me the rates again",
      interpretation: interpretation(intent: "greeting", topic: "general"),
      active_branch: active_branch,
      decision: { action: :booking, pending_question: "confirm_selection" }
    )

    branch = result.dig(:slots_payload, "booking_task", "branch")
    expect(result[:reply_type]).to eq(:ask_rate_plan)
    expect(result[:pending_question]).to eq("rate_plan_selection")
    expect(branch["selected_option"]["selection_id"]).to eq("garden_1")
    expect(branch["selected_option"]).not_to have_key("selected_rate_plan")
    expect(branch["selected_rate_plan_id"]).to be_nil
    expect(branch["selected_rate_plan_name"]).to be_nil
    expect(branch["confirmation_candidate"]).to be_nil
  end

  it "re-asks confirmation when changing rate for an option with a single rate plan" do
    selected_option = option(1, "garden_1", "2026-08-01").merge(
      "rate_plans" => [
        { "rate_plan_id" => 10, "name" => "Standard Rate", "total_price" => 240.0, "currency" => "MYR" }
      ]
    )
    active_branch = branch_with_options([ group("Garden Prestige Suite", [ selected_option ]) ]).merge(
      "selected_option" => selected_option,
      "confirmation_candidate" => selected_option
    )

    result = orchestrate(
      message: "change rate",
      interpretation: interpretation(intent: "greeting", topic: "general"),
      active_branch: active_branch,
      decision: { action: :booking, pending_question: "confirm_selection" }
    )

    branch = result.dig(:slots_payload, "booking_task", "branch")
    expect(result[:reply_type]).to eq(:ask_confirmation)
    expect(result[:pending_question]).to eq("confirm_selection")
    expect(branch["selected_option"]["selection_id"]).to eq("garden_1")
    expect(branch["confirmation_candidate"]["selection_id"]).to eq("garden_1")
    expect(branch["selected_rate_plan_id"]).to eq(10)
    expect(branch["selected_rate_plan_name"]).to eq("Standard Rate")
  end

  it "returns to option selection when a booking-ready guest changes room" do
    selected_option = option(1, "garden_1", "2026-08-01").merge(
      "selected_rate_plan" => { "rate_plan_id" => 10, "name" => "Standard Rate" }
    )
    suggested_options = [
      group("Garden Prestige Suite", [ selected_option ]),
      group("Deluxe Room", [ option(1, "deluxe_1", "2026-08-01") ])
    ]
    active_branch = branch_with_options(suggested_options).merge(
      "selected_option" => selected_option,
      "confirmation_candidate" => selected_option,
      "selected_rate_plan_id" => 10,
      "selected_rate_plan_name" => "Standard Rate"
    )

    result = orchestrate(
      message: "change room",
      interpretation: interpretation(intent: "greeting", topic: "general"),
      active_branch: active_branch,
      decision: { action: :booking, pending_question: "confirm_selection" }
    )

    branch = result.dig(:slots_payload, "booking_task", "branch")
    expect(result[:reply_type]).to eq(:suggest_options)
    expect(result[:pending_question]).to eq("select_option")
    expect(branch["target_month"]).to eq(8)
    expect(branch["adults"]).to eq(2)
    expect(branch["suggested_options"].size).to eq(2)
    expect(branch["selected_option"]).to be_nil
    expect(branch["confirmation_candidate"]).to be_nil
    expect(branch["selected_rate_plan_id"]).to be_nil
    expect(branch["selected_rate_plan_name"]).to be_nil
  end

  it "selects a new option from the same change-room message" do
    selected_option = option(1, "garden_1", "2026-08-01").merge(
      "selected_rate_plan" => { "rate_plan_id" => 10, "name" => "Standard Rate" }
    )
    deluxe_option = option(2, "deluxe_2", "2026-08-02").merge(
      "rate_plans" => [
        { "rate_plan_id" => 20, "name" => "Standard Rate", "total_price" => 260.0, "currency" => "MYR" },
        { "rate_plan_id" => 21, "name" => "Flexible Rate", "total_price" => 290.0, "currency" => "MYR" }
      ]
    )
    active_branch = branch_with_options([
      group("Garden Prestige Suite", [ selected_option ]),
      group("Deluxe Room", [ deluxe_option ])
    ]).merge(
      "selected_option" => selected_option,
      "confirmation_candidate" => selected_option,
      "selected_rate_plan_id" => 10,
      "selected_rate_plan_name" => "Standard Rate"
    )

    result = orchestrate(
      message: "change room to deluxe room option 2",
      interpretation: interpretation(intent: "option_selection", slots: { "option_number" => 2 }),
      active_branch: active_branch,
      decision: { action: :booking, pending_question: "confirm_selection" }
    )

    branch = result.dig(:slots_payload, "booking_task", "branch")
    expect(result[:reply_type]).to eq(:ask_rate_plan)
    expect(result[:pending_question]).to eq("rate_plan_selection")
    expect(branch["selected_option"]["selection_id"]).to eq("deluxe_2")
    expect(branch["confirmation_candidate"]).to be_nil
    expect(branch["selected_rate_plan_id"]).to be_nil
  end

  # The date has to leave the branch as it is named, or the ladder says the
  # same sentence every turn and the guest cannot get past it.
  it "names a check-in date that has passed and forgets it", frozen_time: Date.new(2026, 8, 20) do
    result = orchestrate(
      message: "3-5 january 2026",
      interpretation: interpretation,
      active_branch: {
        "check_in" => "2026-01-03", "check_out" => "2026-01-05",
        "target_month" => 1, "target_year" => 2026, "nights" => 2, "adults" => 2
      },
      decision: { action: :booking, pending_question: nil }
    )

    expect(result[:reply_type]).to eq(:timing_in_the_past)
    expect(result[:pending_question]).to eq("booking_timing")
    expect(result.dig(:extra_context, :check_in)).to eq("2026-01-03")

    branch = result.dig(:slots_payload, "booking_task", "branch")
    expect(branch["check_in"]).to be_blank
    expect(branch["target_month"]).to be_blank
  end

  # A booking picked up after an interruption used to be answered by a class of
  # its own, which read the branch out of Postgres and never looked at the one
  # the guest's own message had just been merged into.
  describe "a booking picked up after an interruption" do
    let(:decision) { { action: :resume, pending_question: "select_option" } }

    it "answers on the branch it was handed, not the one in the record" do
      result = orchestrate(
        message: "1",
        interpretation: interpretation(intent: "option_selection", slots: {}),
        active_branch: branch_with_options([
          group("Deluxe Room", [ option(1, "deluxe_1", "2026-08-01") ])
        ])
      )

      expect(result[:reply_type]).to eq(:ask_confirmation)
      expect(result.dig(:extra_context, :selected_option, "selection_id")).to eq("deluxe_1")
    end

    # The guest was away, not failing to answer. "Sorry, I didn't catch that."
    # is what a counter that counted this turn would put in front of the reply.
    it "offers the saved list again rather than telling the guest off" do
      conversation_state.update!(slots_payload: reasked_payload(saved_branch))

      result = orchestrate(
        message: "hello again",
        interpretation: interpretation(intent: "option_selection", slots: {}),
        active_branch: saved_branch
      )

      expect(result[:reply_type]).to eq(:resume_options)
      expect(result[:pending_question]).to eq("select_option")
      expect(result.dig(:extra_context, :options)).to be_present
      expect(result.dig(:slots_payload, "booking_task", "reask_count")).to eq(0)
      expect(result[:needs_human_support]).to be(false)
    end

    # A question already asked twice over a branch that did not move: one more
    # count and the thread asks for a person.
    def reasked_payload(branch)
      AiConcierge::State::ConversationTaskManager
        .new(slots_payload: AiConcierge::State::ConversationTaskManager.new(slots_payload: {}).activate_booking(branch, pending_question: "select_option"))
        .activate_booking(branch, pending_question: "select_option", count_reask: true)
    end

    def saved_branch
      @saved_branch ||= branch_with_options([
        group("Garden Prestige Suite", [ option(1, "garden_1", "2026-08-01"), option(2, "garden_2", "2026-08-02") ])
      ])
    end
  end

  def orchestrate(message:, interpretation:, active_branch:, decision: self.decision)
    described_class.new(
      hotel: hotel,
      prospect: prospect,
      conversation_state: conversation_state,
      interpretation: interpretation,
      active_branch: active_branch,
      decision: decision,
      message: message,
      phone: prospect.phone_number,
      tool_registry: tool_registry
    ).call
  end

  def interpretation(intent: "booking_search", topic: "booking_search", slots: {})
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
      }
    }
  end

  def branch_with_options(options)
    {
      "branch_id" => "branch-1",
      "target_month" => 8,
      "target_year" => 2026,
      "month_segment" => "early",
      "days" => 2,
      "nights" => 1,
      "adults" => 2,
      "children" => 0,
      "suggestion_set_version" => 3,
      "suggested_options" => options
    }
  end

  def default_active_branch
    branch_with_options([
      group("Garden Prestige Suite", [ option(1, "garden_1", "2026-08-01") ])
    ])
  end

  def group(room_type_name, options)
    {
      "room_type_name" => room_type_name,
      "options" => options.map { |option| option.merge("room_type_name" => room_type_name) }
    }
  end

  def option(position, selection_id, check_in)
    {
      "position" => position,
      "selection_id" => selection_id,
      "check_in" => check_in,
      "check_out" => Date.parse(check_in).next_day.iso8601,
      "nights" => 1,
      "total_price" => 220.0,
      "currency" => "MYR"
    }
  end
end
