require "rails_helper"

RSpec.describe AiConciergeV3::TransitionPolicy do
  let(:interpretation) do
    {
      "intent" => "booking_search",
      "conversation_signals" => {
        "is_reset" => false,
        "is_resume" => false,
        "is_correction" => false,
        "starts_new_booking_branch" => false
      }
    }
  end

  it "asks for booking timing when timing is missing" do
    result = described_class.new(
      interpretation: interpretation,
      active_branch: { "adults" => 2, "children" => 0 },
      paused_flows: [],
      pending_question: nil
    ).call

    expect(result[:action]).to eq(:ask_booking_timing)
  end

  it "asks for duration when a month window is provided without stay length" do
    result = described_class.new(
      interpretation: interpretation,
      active_branch: { "target_month" => 8, "target_year" => 2026, "month_segment" => "early", "adults" => 2, "children" => 0 },
      paused_flows: [],
      pending_question: nil
    ).call

    expect(result[:action]).to eq(:ask_duration)
  end

  it "asks for duration when only check-in is provided" do
    result = described_class.new(
      interpretation: interpretation,
      active_branch: { "check_in" => "2026-08-03", "adults" => 2, "children" => 0 },
      paused_flows: [],
      pending_question: nil
    ).call

    expect(result[:action]).to eq(:ask_duration)
  end

  it "asks for guest count when timing and duration exist but guests are missing" do
    result = described_class.new(
      interpretation: interpretation,
      active_branch: { "target_month" => 8, "target_year" => 2026, "month_segment" => "early", "nights" => 2, "days" => 3 },
      paused_flows: [],
      pending_question: nil
    ).call

    expect(result[:action]).to eq(:ask_guest_count)
  end

  it "asks for adult count when only children are provided" do
    result = described_class.new(
      interpretation: interpretation,
      active_branch: { "target_month" => 8, "target_year" => 2026, "month_segment" => "early", "nights" => 2, "days" => 3, "children" => 2 },
      paused_flows: [],
      pending_question: nil
    ).call

    expect(result[:action]).to eq(:ask_adult_count)
  end

  it "asks for party split when total guest count is known but composition is not" do
    result = described_class.new(
      interpretation: interpretation,
      active_branch: { "target_month" => 8, "target_year" => 2026, "month_segment" => "early", "nights" => 2, "days" => 3, "party_size_total" => 2 },
      paused_flows: [],
      pending_question: nil
    ).call

    expect(result[:action]).to eq(:ask_party_split)
  end

  it "searches when timing, duration, and guest split are resolved" do
    result = described_class.new(
      interpretation: interpretation,
      active_branch: { "check_in" => "2026-08-03", "check_out" => "2026-08-05", "nights" => 2, "days" => 3, "adults" => 2, "children" => 0 },
      paused_flows: [],
      pending_question: nil
    ).call

    expect(result[:action]).to eq(:search_options)
  end

  it "resumes paused option selections before validating them" do
    result = described_class.new(
      interpretation: interpretation.merge("intent" => "option_selection"),
      active_branch: {},
      paused_flows: [{ "topic" => "booking_search" }],
      pending_question: nil,
      message: "option 2"
    ).call

    expect(result[:action]).to eq(:resume)
  end

  it "resumes a paused booking flow for room type and date follow-ups" do
    result = described_class.new(
      interpretation: interpretation.merge("slots" => { "check_in" => "2026-05-22" }),
      active_branch: {},
      paused_flows: [
        {
          "topic" => "booking_search",
          "slots" => {
            "suggested_options" => [
              { "room_type_name" => "Executive Penthouse", "options" => [] }
            ]
          }
        }
      ],
      pending_question: nil,
      message: "ok i want to book executive on may 22"
    ).call

    expect(result[:action]).to eq(:resume)
  end
end
