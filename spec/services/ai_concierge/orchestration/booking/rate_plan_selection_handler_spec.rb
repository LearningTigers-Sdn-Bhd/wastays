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

  # The rate list is numbered the way the catalogue is, and read the same way.
  it "stores the rate plan the guest numbered and asks for confirmation" do
    active_branch = { "selected_option" => selected_option }

    result = described_class.new(message: "no 2").call(
      conversation_state: conversation_state,
      active_branch: active_branch
    )

    expect(result[:reply_type]).to eq(:ask_confirmation)
    expect(result[:pending_question]).to eq("confirm_selection")
    expect(result.dig(:extra_context, :selected_option, "selected_rate_plan", "rate_plan_id")).to eq(11)
    expect(result.dig(:slots_payload, "booking_task", "branch", "selected_rate_plan_id")).to eq(11)
  end

  # The old matcher only understood first, second and third.
  it "reaches a rate plan past the third row" do
    selected_option["rate_plans"] << { "rate_plan_id" => 13, "name" => "Long Stay Rate", "total_price" => 300.0, "currency" => "MYR" }

    result = described_class.new(message: "option 4").call(
      conversation_state: conversation_state,
      active_branch: { "selected_option" => selected_option }
    )

    expect(result.dig(:slots_payload, "booking_task", "branch", "selected_rate_plan_id")).to eq(13)
  end

  it "takes the only rate plan without asking" do
    result = described_class.new(message: "anything at all").call(
      conversation_state: conversation_state,
      active_branch: { "selected_option" => selected_option.merge("rate_plans" => [ selected_option["rate_plans"].first ]) }
    )

    expect(result[:reply_type]).to eq(:ask_confirmation)
    expect(result.dig(:slots_payload, "booking_task", "branch", "selected_rate_plan_id")).to eq(10)
  end

  # A rate plan's name is no longer a way in, so naming one re-asks.
  it "re-asks for the rate plan when the reply carries no row" do
    [ "non refundable", "standard", "the cheapest one" ].each do |message|
      result = described_class.new(message: message).call(
        conversation_state: conversation_state,
        active_branch: { "selected_option" => selected_option }
      )

      expect(result[:reply_type]).to eq(:ask_rate_plan), "expected #{message.inspect} to re-ask"
      expect(result[:pending_question]).to eq("rate_plan_selection")
      expect(result.dig(:extra_context, :rate_plans).size).to eq(3)
    end
  end

  it "returns nothing when there is no room left to price" do
    result = described_class.new(message: "1").call(
      conversation_state: conversation_state,
      active_branch: { "selected_option" => nil }
    )

    expect(result).to be_nil
  end
end
