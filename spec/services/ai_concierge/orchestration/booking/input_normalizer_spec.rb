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
    with_frozen_time Date.new(2026, 6, 3) do
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
    with_frozen_time Date.new(2026, 6, 3) do
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
    with_frozen_time Date.new(2026, 6, 3) do
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
    with_frozen_time Date.new(2026, 6, 3) do
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
    with_frozen_time Date.new(2026, 6, 3) do
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
    with_frozen_time Date.new(2026, 6, 3) do
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
    with_frozen_time Date.new(2026, 6, 3) do
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
    with_frozen_time Date.new(2026, 6, 3) do
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
    with_frozen_time Date.new(2026, 6, 3) do
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
    with_frozen_time Date.new(2026, 5, 1) do
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
    with_frozen_time Date.new(2026, 5, 1) do
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
    with_frozen_time Date.new(2026, 6, 3) do
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
    with_frozen_time Date.new(2026, 12, 1) do
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
    with_frozen_time Date.new(2026, 12, 1) do
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
    with_frozen_time Date.new(2026, 12, 3) do
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

  it "drops a party size the message never stated" do
    result = described_class.new(
      message: "3 nights",
      slots: { "nights" => 3, "adults" => 1 },
      pending_question: "duration",
      conversation_signals: signals
    ).call

    expect(result["nights"]).to eq(3)
    expect(result).not_to have_key("adults")
  end

  it "keeps a party size stated without a number when guest count was asked" do
    result = described_class.new(
      message: "me and my wife",
      slots: { "adults" => 2 },
      pending_question: "guest_count",
      conversation_signals: signals
    ).call

    expect(result["adults"]).to eq(2)
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

  it "drops a hallucinated month quoted with words that say nothing about time" do
    result = described_class.new(
      message: "how to make booking",
      slots: { "target_month" => 8, "target_year" => 2026 },
      pending_question: nil,
      conversation_signals: signals,
      evidence: { "timing" => "booking" }
    ).call

    expect(result).not_to include("target_month", "target_year")
  end

  it "drops a hallucinated checkout quoted with words that say nothing about time" do
    result = described_class.new(
      message: "saya nak book bilik",
      slots: { "check_in" => "2026-08-20", "check_out" => "2026-08-22" },
      pending_question: nil,
      conversation_signals: signals,
      evidence: { "timing" => "book", "checkout" => "book" }
    ).call

    expect(result).not_to include("check_in", "check_out")
  end

  it "keeps a date quoted in a language the English guards cannot read" do
    malay = described_class.new(
      message: "28 Ogos",
      slots: { "check_in" => "2026-08-28" },
      pending_question: nil,
      conversation_signals: signals,
      evidence: { "timing" => "28 Ogos" }
    ).call
    chinese = described_class.new(
      message: "8月28号",
      slots: { "check_in" => "2026-08-28" },
      pending_question: nil,
      conversation_signals: signals,
      evidence: { "timing" => "8月28号" }
    ).call

    expect(malay["check_in"]).to eq("2026-08-28")
    expect(chinese["check_in"]).to eq("2026-08-28")
  end

  it "keeps a relative month named without a digit" do
    chinese = described_class.new(
      message: "下个月",
      slots: { "target_month" => 9, "target_year" => 2026 },
      pending_question: nil,
      conversation_signals: signals,
      evidence: { "timing" => "下个月" }
    ).call
    malay = described_class.new(
      message: "bulan depan",
      slots: { "target_month" => 9, "target_year" => 2026 },
      pending_question: nil,
      conversation_signals: signals,
      evidence: { "timing" => "bulan depan" }
    ).call

    expect(chinese["target_month"]).to eq(9)
    expect(malay["target_month"]).to eq(9)
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

  # A live thread: the guest answered the numbered catalogue with "option 1",
  # the model quoted the 1 as the words that say the party size, and a booking
  # for three became a booking for one adult -- which discarded the catalogue
  # and asked how many of the remaining two were children.
  it "drops a party size quoted from nothing but a number" do
    result = described_class.new(
      message: "option 1",
      slots: { "adults" => 1 },
      pending_question: "select_option",
      conversation_signals: signals,
      evidence: { "party" => "1" }
    ).call

    expect(result).not_to include("adults", "party_size_total", "children")
  end

  it "drops a party size quoted from an option reference" do
    result = described_class.new(
      message: "option 1",
      slots: { "adults" => 1 },
      pending_question: "select_option",
      conversation_signals: signals,
      evidence: { "party" => "option 1" }
    ).call

    expect(result).not_to include("adults")
  end

  it "keeps a party size quoted in a language the English guards cannot read" do
    result = described_class.new(
      message: "两位大人",
      slots: { "adults" => 2 },
      pending_question: "guest_count",
      conversation_signals: signals,
      evidence: { "party" => "两位大人" }
    ).call

    expect(result["adults"]).to eq(2)

    malay = described_class.new(
      message: "tiga dewasa",
      slots: { "adults" => 3 },
      pending_question: "select_option",
      conversation_signals: signals,
      evidence: { "party" => "tiga dewasa" }
    ).call

    expect(malay["adults"]).to eq(3)
  end

  # "no 2" answering "which rate would you like?" came back as two nights, and
  # the changed search discarded the room the guest had just chosen -- leaving
  # the rate question with no room to ask about.
  it "reads a bare row reference as a row, not as a search slot" do
    result = described_class.new(
      message: "no 2",
      slots: { "nights" => 2, "days" => 2, "room_count" => 2, "adults" => 2 },
      pending_question: "rate_plan_selection",
      conversation_signals: signals,
      evidence: { "duration" => "2", "party" => "2" }
    ).call

    expect(result).to be_empty
  end

  it "reads a bare option number as a row while the catalogue is on the table" do
    result = described_class.new(
      message: "option 1",
      slots: { "adults" => 1, "nights" => 1 },
      pending_question: "select_option",
      conversation_signals: signals,
      evidence: { "party" => "1", "duration" => "1" }
    ).call

    expect(result).to be_empty
  end

  # The rule is about messages that say nothing else. A duration the guest
  # actually stated still counts, wherever they state it.
  it "keeps a duration stated in words while a list is on the table" do
    result = described_class.new(
      message: "2 nights",
      slots: { "nights" => 2 },
      pending_question: "rate_plan_selection",
      conversation_signals: signals,
      evidence: { "duration" => "2 nights" }
    ).call

    expect(result["nights"]).to eq(2)
  end

  it "still answers a guest count question with a bare number" do
    result = described_class.new(
      message: "2",
      slots: { "party_size_total" => 2 },
      pending_question: "guest_count",
      conversation_signals: signals
    ).call

    expect(result["party_size_total"]).to eq(2)
  end

  # "2" answering "how many days and nights will you be staying?" said nothing
  # the guards recognised, so the duration was dropped and the same question
  # came back -- for as long as the guest kept answering it the short way.
  it "reads a bare number answering the duration question as nights" do
    result = described_class.new(
      message: "2",
      slots: {},
      pending_question: "duration",
      conversation_signals: signals
    ).call

    expect(result["nights"]).to eq(2)
  end

  it "leaves a bare number alone when the duration was not the question" do
    result = described_class.new(
      message: "2",
      slots: {},
      pending_question: "specific_timing",
      conversation_signals: signals
    ).call

    expect(result).not_to include("nights")
  end
end
