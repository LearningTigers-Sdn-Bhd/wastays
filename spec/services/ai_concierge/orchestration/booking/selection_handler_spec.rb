require "rails_helper"

RSpec.describe AiConcierge::Orchestration::Booking::SelectionHandler do
  let(:conversation_state) { build_stubbed(:prospect_conversation_state, slots_payload: {}) }

  it "asks for rate plan selection when the selected option has multiple plans" do
    selected_option = option.merge(
      "rate_plans" => [
        { "rate_plan_id" => 10, "name" => "Standard Rate" },
        { "rate_plan_id" => 11, "name" => "Flexible Rate" }
      ]
    )
    handler = described_class.new(tool_registry: registry_with(success_result(selected_option)), message: "option 1")

    result = handler.handle_selection(
      conversation_state: conversation_state,
      interpretation: interpretation(slots: { "option_number" => 1 }),
      active_branch: active_branch
    )

    expect(result[:reply_type]).to eq(:ask_rate_plan)
    expect(result[:pending_question]).to eq("rate_plan_selection")
    expect(result.dig(:slots_payload, "booking_task", "branch", "selected_option", "selection_id")).to eq("garden_1")
  end

  it "takes the rate plan from the same message as the room" do
    selected_option = option.merge("room_type_name" => "Garden Suite", "rate_plans" => two_rate_plans)
    handler = described_class.new(tool_registry: registry_with(success_result(selected_option)), message: "garden suite for standard rate")

    result = handler.handle_selection(
      conversation_state: conversation_state,
      interpretation: interpretation,
      active_branch: active_branch
    )

    expect(result[:reply_type]).to eq(:ask_confirmation)
    expect(result[:pending_question]).to eq("confirm_selection")
    expect(result.dig(:slots_payload, "booking_task", "branch", "selected_rate_plan_name")).to eq("Standard Rate")
  end

  it "does not read an option number on the turn as a rate plan" do
    selected_option = option.merge("room_type_name" => "Garden Suite", "rate_plans" => two_rate_plans)
    handler = described_class.new(tool_registry: registry_with(success_result(selected_option)), message: "garden suite option 2")

    result = handler.handle_selection(
      conversation_state: conversation_state,
      interpretation: interpretation(slots: { "option_number" => 2 }),
      active_branch: active_branch
    )

    expect(result[:reply_type]).to eq(:ask_rate_plan)
    expect(result.dig(:slots_payload, "booking_task", "branch", "selected_rate_plan_name")).to be_nil
  end

  it "does not read the room's own name as a rate plan" do
    selected_option = option.merge("room_type_name" => "Standard Room", "rate_plans" => two_rate_plans)
    handler = described_class.new(tool_registry: registry_with(success_result(selected_option)), message: "standard room")

    result = handler.handle_selection(
      conversation_state: conversation_state,
      interpretation: interpretation,
      active_branch: active_branch
    )

    expect(result[:reply_type]).to eq(:ask_rate_plan)
    expect(result.dig(:slots_payload, "booking_task", "branch", "selected_rate_plan_name")).to be_nil
  end

  it "carries selection disambiguation context when the tool cannot choose" do
    handler = described_class.new(
      tool_registry: registry_with({
        "success" => false,
        "error" => "room_type_requires_option_number",
        "room_type_name" => "Garden Suite",
        "check_in" => "2026-08-01"
      }),
      message: "garden suite"
    )

    result = handler.handle_selection(
      conversation_state: conversation_state,
      interpretation: interpretation,
      active_branch: active_branch
    )

    expect(result[:reply_type]).to eq(:room_type_requires_option_number)
    expect(result[:pending_question]).to eq("select_option")
    expect(result.dig(:extra_context, :room_type_name)).to eq("Garden Suite")
    expect(result.dig(:slots_payload, "booking_task", "branch", "pending_selection", "room_type_name")).to eq("Garden Suite")
  end

  it "resolves a follow-up selection into an option_selection interpretation" do
    handler = described_class.new(tool_registry: registry_with(success_result(option)), message: "garden suite")

    result = handler.resolve_follow_up(
      conversation_state: conversation_state,
      interpretation: interpretation,
      active_branch: active_branch,
      pending_question: "select_option"
    )

    expect(result["intent"]).to eq("option_selection")
    expect(result.dig("slots", "selection_id")).to eq("garden_1")
  end

  def registry_with(result)
    tool = Class.new do
      define_method(:initialize) { |**| }
      define_method(:call) { result }
    end

    { "select_booking_option" => tool }
  end

  def two_rate_plans
    [
      { "rate_plan_id" => 10, "name" => "Standard Rate" },
      { "rate_plan_id" => 11, "name" => "Flexible Rate" }
    ]
  end

  def success_result(selected_option)
    { "success" => true, "selected_option" => selected_option }
  end

  def active_branch
    {
      "suggestion_set_version" => 3,
      "suggested_options" => [
        {
          "room_type_name" => "Garden Suite",
          "options" => [ option.merge("room_type_name" => "Garden Suite") ]
        }
      ]
    }
  end

  def option
    {
      "position" => 1,
      "selection_id" => "garden_1",
      "check_in" => "2026-08-01",
      "check_out" => "2026-08-02"
    }
  end

  def interpretation(slots: {})
    { "intent" => "booking_search", "slots" => slots, "conversation_signals" => {} }
  end
end
