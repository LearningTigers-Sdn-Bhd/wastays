require "rails_helper"

RSpec.describe AiConciergeV3::Orchestration::Booking::ActionResolver do
  it "asks for booking timing before any downstream booking action" do
    action = described_class.new(
      interpretation: interpretation(intent: "booking_search", slots: {}),
      active_branch: {},
      pending_question: nil
    ).call

    expect(action).to eq(:ask_booking_timing)
  end

  it "asks for a rate plan while rate plan selection is pending" do
    action = described_class.new(
      interpretation: interpretation(intent: "booking_search", slots: {}),
      active_branch: branch_with_required_booking_slots,
      pending_question: "rate_plan_selection"
    ).call

    expect(action).to eq(:rate_plan_selection)
  end

  it "routes confirmation yes and no from confirm selection" do
    yes_action = described_class.new(
      interpretation: interpretation(intent: "confirmation", slots: { "confirmation" => "yes" }),
      active_branch: branch_with_required_booking_slots,
      pending_question: "confirm_selection"
    ).call
    no_action = described_class.new(
      interpretation: interpretation(intent: "confirmation", slots: { "confirmation" => "no" }),
      active_branch: branch_with_required_booking_slots,
      pending_question: "confirm_selection"
    ).call

    expect(yes_action).to eq(:confirmation_yes)
    expect(no_action).to eq(:confirmation_no)
  end

  it "searches options when required booking slots are complete" do
    action = described_class.new(
      interpretation: interpretation(intent: "booking_search", slots: {}),
      active_branch: branch_with_required_booking_slots,
      pending_question: nil
    ).call

    expect(action).to eq(:search_options)
  end

  def interpretation(intent:, slots:)
    { "intent" => intent, "slots" => slots }
  end

  def branch_with_required_booking_slots
    {
      "target_month" => 8,
      "target_year" => 2026,
      "month_segment" => "mid",
      "nights" => 2,
      "days" => 3,
      "adults" => 2,
      "children" => 0,
      "party_size_total" => nil
    }
  end
end
