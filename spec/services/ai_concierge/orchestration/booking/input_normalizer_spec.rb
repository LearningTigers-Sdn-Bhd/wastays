require "rails_helper"

RSpec.describe AiConcierge::Orchestration::Booking::InputNormalizer do
  it "removes hallucinated timing from vague booking messages" do
    result = described_class.new(
      message: "hello, is there any booking for 2 adults",
      slots: { "target_month" => 5, "target_year" => 2026, "month_segment" => "early", "adults" => 2 },
      pending_question: nil,
      conversation_signals: signals
    ).call

    expect(result).not_to include("target_month", "target_year", "month_segment")
    expect(result["adults"]).to eq(2)
  end

  it "keeps specific timing when answering a specific timing clarification" do
    result = described_class.new(
      message: "early july",
      slots: { "target_month" => 7, "target_year" => 2026, "month_segment" => "early" },
      pending_question: "specific_timing",
      conversation_signals: signals
    ).call

    expect(result["target_month"]).to eq(7)
    expect(result["month_segment"]).to eq("early")
  end

  it "extracts this-month timing even when the LLM returns no timing slots" do
    travel_to Date.new(2026, 6, 3) do
      result = described_class.new(
        message: "late this month have?",
        slots: {},
        pending_question: "booking_timing",
        conversation_signals: signals
      ).call

      expect(result).to include(
        "target_month" => 6,
        "target_year" => 2026,
        "month_segment" => "late"
      )
    end
  end

  it "clears a stale month segment when this-month timing has no segment" do
    travel_to Date.new(2026, 6, 3) do
      result = described_class.new(
        message: "nice, can i book for this month?",
        slots: {},
        pending_question: "booking_timing",
        conversation_signals: signals,
        active_branch: { "target_month" => 7, "target_year" => 2026, "month_segment" => "late" }
      ).call

      expect(result).to include(
        "target_month" => 6,
        "target_year" => 2026,
        "month_segment" => ""
      )
    end
  end

  it "extracts a specific date answer with an affirmative suffix" do
    result = described_class.new(
      message: "23 june ok?",
      slots: { "confirmation" => "yes" },
      pending_question: "specific_timing",
      conversation_signals: signals,
      active_branch: { "target_month" => 6, "target_year" => 2026 }
    ).call

    expect(result["check_in"]).to eq("2026-06-23")
    expect(result["target_month"]).to eq(6)
    expect(result["target_year"]).to eq(2026)
    expect(result).not_to include("confirmation")
  end

  it "extracts a day-only answer from the active month context" do
    result = described_class.new(
      message: "23",
      slots: {},
      pending_question: "specific_timing",
      conversation_signals: signals,
      active_branch: { "target_month" => 6, "target_year" => 2026 }
    ).call

    expect(result["check_in"]).to eq("2026-06-23")
  end

  it "keeps duration only when duration is explicit" do
    result = described_class.new(
      message: "3 days 2 nights",
      slots: { "days" => 3, "nights" => 2 },
      pending_question: "duration",
      conversation_signals: signals
    ).call

    expect(result).to include("days" => 3, "nights" => 2)
  end

  it "extracts numeric guest count for guest-count answers" do
    result = described_class.new(
      message: "2",
      slots: { "party_size_total" => 1, "adults" => 2 },
      pending_question: "guest_count",
      conversation_signals: signals
    ).call

    expect(result["party_size_total"]).to eq(2)
    expect(result).not_to have_key("adults")
  end

  it "does not filter correction turns" do
    result = described_class.new(
      message: "actually late august",
      slots: { "target_month" => 8, "target_year" => 2026, "month_segment" => "late" },
      pending_question: "duration",
      conversation_signals: signals.merge("is_correction" => true)
    ).call

    expect(result).to include("target_month" => 8, "month_segment" => "late")
  end

  def signals
    {
      "is_reset" => false,
      "is_resume" => false,
      "is_correction" => false,
      "starts_new_booking_branch" => false,
      "end_conversation" => false
    }
  end
end
