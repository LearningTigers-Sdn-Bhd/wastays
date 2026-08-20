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

  # Both lists are answered by position, so a number on this turn is the row of
  # the catalogue and cannot also be a row of the rate list. Naming a rate is no
  # longer a way in either -- so a room with more than one plan always asks.
  it "always asks which rate when the room has more than one plan" do
    [ "option 1", "garden suite for standard rate", "standard room", "1 non refundable" ].each do |message|
      selected_option = option.merge("room_type_name" => "Garden Suite", "rate_plans" => two_rate_plans)
      handler = described_class.new(tool_registry: registry_with(success_result(selected_option)), message: message)

      result = handler.handle_selection(
        conversation_state: conversation_state,
        interpretation: interpretation(slots: { "option_number" => 1 }),
        active_branch: active_branch
      )

      expect(result[:reply_type]).to eq(:ask_rate_plan), "expected #{message.inspect} to ask which rate"
      expect(result.dig(:slots_payload, "booking_task", "branch", "selected_rate_plan_name")).to be_nil
    end
  end

  it "goes straight to confirmation when the room has a single plan" do
    selected_option = option.merge("rate_plans" => [ { "rate_plan_id" => 10, "name" => "Standard Rate" } ])
    handler = described_class.new(tool_registry: registry_with(success_result(selected_option)), message: "1")

    result = handler.handle_selection(
      conversation_state: conversation_state,
      interpretation: interpretation(slots: { "option_number" => 1 }),
      active_branch: active_branch
    )

    expect(result[:reply_type]).to eq(:ask_confirmation)
    expect(result[:pending_question]).to eq("confirm_selection")
    expect(result.dig(:slots_payload, "booking_task", "branch", "confirmation_candidate", "selected_rate_plan", "name")).to eq("Standard Rate")
  end

  it "asks for the number again when the tool cannot match the message" do
    handler = described_class.new(
      tool_registry: registry_with({ "success" => false, "error" => "invalid_selection" }),
      message: "garden suite"
    )

    result = handler.handle_selection(
      conversation_state: conversation_state,
      interpretation: interpretation,
      active_branch: active_branch
    )

    expect(result[:reply_type]).to eq(:invalid_selection)
    expect(result[:pending_question]).to eq("select_option")
  end

  it "resolves a follow-up selection into an option_selection interpretation" do
    handler = described_class.new(tool_registry: registry_with(success_result(option)), message: "1")

    result = handler.resolve_follow_up(
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
