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

  it "selects the only visible option when the guest replies with the room type" do
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

  it "asks for an option number when the named room type has multiple visible options" do
    result = orchestrate(
      message: "garden prestige suite",
      interpretation: interpretation,
      active_branch: branch_with_options([
        group("Garden Prestige Suite", [ option(1, "garden_1", "2026-08-01"), option(2, "garden_2", "2026-08-02") ])
      ])
    )

    expect(result[:reply_type]).to eq(:room_type_requires_option_number)
    expect(result[:pending_question]).to eq("select_option")
    expect(result.dig(:extra_context, :room_type_name)).to eq("Garden Prestige Suite")
    expect(result.dig(:slots_payload, "booking_task", "branch", "pending_selection", "room_type_name")).to eq("Garden Prestige Suite")
  end

  it "asks for room type clarification when an option number is ambiguous" do
    result = orchestrate(
      message: "option 1",
      interpretation: interpretation(slots: { "option_number" => 1 }),
      active_branch: branch_with_options([
        group("Garden Prestige Suite", [ option(1, "garden_1", "2026-08-01") ]),
        group("Deluxe Room", [ option(1, "deluxe_1", "2026-08-01") ])
      ])
    )

    expect(result[:reply_type]).to eq(:ambiguous_option_selection)
    expect(result[:pending_question]).to eq("select_option")
    expect(result.dig(:extra_context, :room_type_names)).to contain_exactly("Garden Prestige Suite", "Deluxe Room")
    expect(result.dig(:extra_context, :option_number)).to eq(1)
  end

  it "asks for room type clarification when a date is ambiguous" do
    result = orchestrate(
      message: "august 1",
      interpretation: interpretation(slots: { "check_in" => "2026-08-01" }),
      active_branch: branch_with_options([
        group("Garden Prestige Suite", [ option(1, "garden_1", "2026-08-01") ]),
        group("Deluxe Room", [ option(1, "deluxe_1", "2026-08-01") ])
      ])
    )

    expect(result[:reply_type]).to eq(:ambiguous_date_selection)
    expect(result[:pending_question]).to eq("select_option")
    expect(result.dig(:extra_context, :room_type_names)).to contain_exactly("Garden Prestige Suite", "Deluxe Room")
    expect(result.dig(:slots_payload, "booking_task", "branch", "pending_selection", "check_in")).to eq("2026-08-01")
  end

  it "uses pending date context when the guest later names the room type" do
    active_branch = branch_with_options([
      group("Ocean Villa King", [ option(1, "ocean_1", "2026-05-21"), option(2, "ocean_2", "2026-05-22") ]),
      group("Executive Penthouse", [ option(1, "exec_1", "2026-05-21") ])
    ]).merge("pending_selection" => { "check_in" => "2026-05-21" })

    result = orchestrate(message: "ocean villa king", interpretation: interpretation, active_branch: active_branch)

    expect(result[:reply_type]).to eq(:ask_confirmation)
    expect(result.dig(:extra_context, :selected_option, "selection_id")).to eq("ocean_1")
    expect(result.dig(:slots_payload, "booking_task", "branch", "pending_selection")).to be_nil
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
    expect(result).to have_key(:slots_payload)
    expect(result).not_to include(flow_status: "ended", end_reason: "booking_url_generated")
  end

  it "selects the cheapest rate plan from natural price language" do
    selected_option = option(1, "garden_1", "2026-08-01").merge(
      "rate_plans" => [
        { "rate_plan_id" => 10, "name" => "Standard Rate", "total_price" => 240.0, "currency" => "MYR" },
        { "rate_plan_id" => 11, "name" => "Non-Refundable Rate", "total_price" => 210.0, "currency" => "MYR" }
      ]
    )
    active_branch = branch_with_options([ group("Garden Prestige Suite", [ selected_option ]) ]).merge("selected_option" => selected_option)

    result = orchestrate(
      message: "the cheapest one please",
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

  it "matches non-refundable without treating refundable as the same plan" do
    selected_option = option(1, "garden_1", "2026-08-01").merge(
      "rate_plans" => [
        { "rate_plan_id" => 10, "name" => "Refundable Rate", "total_price" => 260.0, "currency" => "MYR" },
        { "rate_plan_id" => 11, "name" => "Non-Refundable Rate", "total_price" => 220.0, "currency" => "MYR" }
      ]
    )
    active_branch = branch_with_options([ group("Garden Prestige Suite", [ selected_option ]) ]).merge("selected_option" => selected_option)

    refundable = orchestrate(
      message: "refundable",
      interpretation: interpretation(slots: {}),
      active_branch: active_branch.deep_dup,
      decision: { action: :booking, pending_question: "rate_plan_selection" }
    )
    non_refundable = orchestrate(
      message: "non refundable",
      interpretation: interpretation(slots: {}),
      active_branch: active_branch.deep_dup,
      decision: { action: :booking, pending_question: "rate_plan_selection" }
    )

    expect(refundable.dig(:extra_context, :selected_option, "selected_rate_plan", "name")).to eq("Refundable Rate")
    expect(non_refundable.dig(:extra_context, :selected_option, "selected_rate_plan", "name")).to eq("Non-Refundable Rate")
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
