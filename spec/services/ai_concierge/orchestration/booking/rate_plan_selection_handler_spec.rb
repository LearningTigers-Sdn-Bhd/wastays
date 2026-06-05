require "rails_helper"

RSpec.describe AiConcierge::Orchestration::Booking::RatePlanSelectionHandler do
  let(:conversation_state) { build_stubbed(:prospect_conversation_state, slots_payload: {}) }
  let(:selected_option) do
    {
      "selection_id" => "garden_1",
      "rate_plans" => [
        { "rate_plan_id" => 10, "name" => "Standard Rate", "total_price" => 240.0, "currency" => "MYR" },
        { "rate_plan_id" => 11, "name" => "Non-Refundable Rate", "total_price" => 210.0, "currency" => "MYR" },
        { "rate_plan_id" => 12, "name" => "Standard Flexible Rate", "total_price" => 260.0, "currency" => "MYR" }
      ]
    }
  end

  it "stores a matched rate plan and asks for confirmation" do
    active_branch = { "selected_option" => selected_option }

    result = described_class.new(message: "non refundable").call(
      conversation_state: conversation_state,
      interpretation: interpretation,
      active_branch: active_branch
    )

    expect(result[:reply_type]).to eq(:ask_confirmation)
    expect(result[:pending_question]).to eq("confirm_selection")
    expect(result.dig(:extra_context, :selected_option, "selected_rate_plan", "rate_plan_id")).to eq(11)
    expect(result.dig(:slots_payload, "booking_task", "branch", "selected_rate_plan_id")).to eq(11)
  end

  it "re-asks for rate plan when the reply is ambiguous" do
    result = described_class.new(message: "standard").call(
      conversation_state: conversation_state,
      interpretation: interpretation(slots: { "rate_plan_name" => "standard" }),
      active_branch: { "selected_option" => selected_option }
    )

    expect(result[:reply_type]).to eq(:ask_rate_plan)
    expect(result[:pending_question]).to eq("rate_plan_selection")
    expect(result.dig(:extra_context, :rate_plans).size).to eq(3)
  end

  def interpretation(slots: {})
    { "intent" => "booking_search", "slots" => slots }
  end
end
