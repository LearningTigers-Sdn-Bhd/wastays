require "rails_helper"

RSpec.describe AiConciergeV3::Orchestration::Booking::RevisionPolicy do
  let(:branch) do
    AiConciergeV3::State::SlotMerger.empty_branch.merge(
      "target_month" => 8,
      "target_year" => 2026,
      "nights" => 2,
      "days" => 3,
      "party_size_total" => 2,
      "adults" => 2,
      "children" => 0,
      "suggested_options" => [
        {
          "room_type_name" => "Deluxe Room",
          "options" => [ { "selection_id" => "deluxe_1" } ]
        }
      ],
      "selected_option" => {
        "room_type_name" => "Deluxe Room",
        "rate_plans" => [
          { "name" => "Standard Rate", "total_price" => 200 },
          { "name" => "Non-Refundable Rate", "total_price" => 180 }
        ]
      }
    )
  end

  let(:interpretation) do
    {
      "intent" => "booking_search",
      "slots" => {},
      "conversation_signals" => { "end_conversation" => false }
    }
  end

  def policy(message:, current_branch: branch, current_interpretation: interpretation, pending_question: "confirm_selection")
    described_class.new(
      message: message,
      interpretation: current_interpretation,
      active_branch: current_branch,
      pending_question: pending_question
    ).call
  end

  it "detects booking-ready rate revision" do
    expect(policy(message: "can I see the rates again?")).to eq(:change_rate)
  end

  it "detects booking-ready room revision" do
    expect(policy(message: "show me another room option")).to eq(:change_option)
  end

  it "does not revise when the message is informational" do
    guarded = interpretation.merge("intent" => "hotel_information")

    expect(policy(message: "show me another room option", current_interpretation: guarded)).to be_nil
  end

  it "does not revise when timing or party slots are being changed" do
    changed_dates = interpretation.deep_merge("slots" => { "check_in" => "2026-08-12" })

    expect(policy(message: "change room to deluxe", current_interpretation: changed_dates)).to be_nil
  end

  it "does not treat rate wording as a revision during rate-plan selection" do
    expect(policy(message: "standard rate please", pending_question: "rate_plan_selection")).to be_nil
  end
end
