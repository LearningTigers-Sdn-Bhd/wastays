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

  it "extracts a same-month dashed date range" do
    travel_to Date.new(2026, 6, 3) do
      result = described_class.new(
        message: "16-18 June",
        slots: {},
        pending_question: "booking_timing",
        conversation_signals: signals
      ).call

      expect(result).to include(
        "target_month" => 6,
        "target_year" => 2026,
        "check_in" => "2026-06-16",
        "check_out" => "2026-06-18",
        "nights" => 2,
        "days" => 3
      )
    end
  end

  it "extracts a same-month spaced date range" do
    travel_to Date.new(2026, 6, 3) do
      result = described_class.new(
        message: "16 18 June",
        slots: {},
        pending_question: "booking_timing",
        conversation_signals: signals
      ).call

      expect(result).to include(
        "check_in" => "2026-06-16",
        "check_out" => "2026-06-18",
        "nights" => 2,
        "days" => 3
      )
    end
  end

  it "asks for month clarification for a monthless dashed date range" do
    result = described_class.new(
      message: "16-18",
      slots: {},
      pending_question: "booking_timing",
      conversation_signals: signals
    ).call

    expect(result).to include(
      "clarification_needed" => {
        "type" => "date_range_month",
        "start_day" => 16,
        "end_day" => 18
      }
    )
    expect(result).not_to include("check_in", "check_out")
  end

  it "asks for month clarification for a monthless spaced date range" do
    result = described_class.new(
      message: "16 18",
      slots: {},
      pending_question: "booking_timing",
      conversation_signals: signals
    ).call

    expect(result.dig("clarification_needed", "start_day")).to eq(16)
    expect(result.dig("clarification_needed", "end_day")).to eq(18)
  end

  it "does not treat party split numbers as a monthless date range" do
    result = described_class.new(
      message: "2 1",
      slots: { "adults" => 2, "children" => 1 },
      pending_question: "party_split",
      conversation_signals: signals
    ).call

    expect(result).not_to include("clarification_needed")
  end

  it "resolves a pending date range with this month" do
    travel_to Date.new(2026, 6, 3) do
      result = described_class.new(
        message: "this month",
        slots: {},
        pending_question: "date_range_month",
        conversation_signals: signals,
        active_branch: pending_date_range_branch
      ).call

      expect(result).to include(
        "check_in" => "2026-06-16",
        "check_out" => "2026-06-18",
        "nights" => 2,
        "days" => 3
      )
    end
  end

  it "resolves a pending date range with next month" do
    travel_to Date.new(2026, 6, 3) do
      result = described_class.new(
        message: "next month",
        slots: {},
        pending_question: "date_range_month",
        conversation_signals: signals,
        active_branch: pending_date_range_branch
      ).call

      expect(result).to include("check_in" => "2026-07-16", "check_out" => "2026-07-18")
    end
  end

  it "resolves a pending date range with a month quantity" do
    travel_to Date.new(2026, 6, 3) do
      result = described_class.new(
        message: "3 months from now",
        slots: {},
        pending_question: "date_range_month",
        conversation_signals: signals,
        active_branch: pending_date_range_branch
      ).call

      expect(result).to include("check_in" => "2026-09-16", "check_out" => "2026-09-18")
    end
  end

  it "resolves a pending date range with a month name" do
    travel_to Date.new(2026, 6, 3) do
      result = described_class.new(
        message: "August",
        slots: {},
        pending_question: "date_range_month",
        conversation_signals: signals,
        active_branch: pending_date_range_branch
      ).call

      expect(result).to include("check_in" => "2026-08-16", "check_out" => "2026-08-18")
    end
  end

  it "lets a complete range replace pending date range days" do
    travel_to Date.new(2026, 6, 3) do
      result = described_class.new(
        message: "July 20-22",
        slots: {},
        pending_question: "date_range_month",
        conversation_signals: signals,
        active_branch: pending_date_range_branch
      ).call

      expect(result).to include("check_in" => "2026-07-20", "check_out" => "2026-07-22")
    end
  end

  it "extracts a cross-month day-month date range" do
    travel_to Date.new(2026, 5, 1) do
      result = described_class.new(
        message: "31 May - 2 June",
        slots: {},
        pending_question: "booking_timing",
        conversation_signals: signals
      ).call

      expect(result).to include(
        "check_in" => "2026-05-31",
        "check_out" => "2026-06-02",
        "nights" => 2,
        "days" => 3
      )
    end
  end

  it "extracts a cross-month month-day date range" do
    travel_to Date.new(2026, 5, 1) do
      result = described_class.new(
        message: "May 31 - June 2",
        slots: {},
        pending_question: "booking_timing",
        conversation_signals: signals
      ).call

      expect(result).to include("check_in" => "2026-05-31", "check_out" => "2026-06-02")
    end
  end

  it "extracts a same-month day-month-to-day date range" do
    travel_to Date.new(2026, 6, 3) do
      result = described_class.new(
        message: "16 June - 18",
        slots: {},
        pending_question: "booking_timing",
        conversation_signals: signals
      ).call

      expect(result).to include("check_in" => "2026-06-16", "check_out" => "2026-06-18", "nights" => 2)
    end
  end

  it "advances checkout year for a cross-year date range" do
    travel_to Date.new(2026, 12, 1) do
      result = described_class.new(
        message: "31 Dec - 2 Jan",
        slots: {},
        pending_question: "booking_timing",
        conversation_signals: signals
      ).call

      expect(result).to include("check_in" => "2026-12-31", "check_out" => "2027-01-02", "nights" => 2)
    end
  end

  it "treats a trailing year on a cross-year range as the checkout year" do
    travel_to Date.new(2026, 12, 1) do
      result = described_class.new(
        message: "31 Dec - 2 Jan 2027",
        slots: {},
        pending_question: "booking_timing",
        conversation_signals: signals
      ).call

      expect(result).to include("check_in" => "2026-12-31", "check_out" => "2027-01-02")
    end
  end

  it "resolves a pending date range month name to the next occurrence" do
    travel_to Date.new(2026, 12, 3) do
      result = described_class.new(
        message: "January",
        slots: {},
        pending_question: "date_range_month",
        conversation_signals: signals,
        active_branch: pending_date_range_branch
      ).call

      expect(result).to include("check_in" => "2027-01-16", "check_out" => "2027-01-18")
    end
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

  def pending_date_range_branch
    {
      "clarification_needed" => {
        "type" => "date_range_month",
        "start_day" => 16,
        "end_day" => 18
      }
    }
  end
end
