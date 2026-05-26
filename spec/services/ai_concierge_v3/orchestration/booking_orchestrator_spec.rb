require "rails_helper"

RSpec.describe AiConciergeV3::Orchestration::BookingOrchestrator do
  let(:hotel) { create(:hotel, :with_ai_concierge) }
  let(:prospect) { create(:prospect, hotel: hotel, phone_number: "+60123456789") }
  let(:conversation_state) { create(:prospect_conversation_state, prospect: prospect, pending_question: pending_question, slots_payload: slots_payload) }
  let(:pending_question) { "select_option" }
  let(:slots_payload) do
    AiConciergeV3::State::ConversationTaskManager.new(slots_payload: {}).activate_booking(default_active_branch, pending_question: pending_question)
  end
  let(:decision) { { action: :booking, pending_question: pending_question } }
  let(:tool_registry) { instance_double(AiConciergeV3::Tools::ToolRegistry) }

  before do
    allow(tool_registry).to receive(:fetch).with("select_booking_option").and_return(AiConciergeV3::Tools::Booking::SelectBookingOptionTool)
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

  it "returns a safe fallback when booking url generation fails without a completion payload" do
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

    expect(result[:direct_payload][:reply_message]).to eq("Unable to generate quote right now.")
    expect(result[:direct_payload][:needs_human_support]).to be(true)
    expect(result).not_to have_key(:slots_payload)
    expect(result).not_to include(flow_status: "ended", end_reason: "booking_url_generated")
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
