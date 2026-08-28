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

  it "extracts a natural segment from a relative month" do
    with_frozen_time Date.new(2026, 8, 28) do
      [ "next month on end month", "end of next month" ].each do |message|
        result = described_class.new(
          message: message,
          slots: {},
          pending_question: "specific_timing",
          conversation_signals: signals
        ).call

        expect(result).to include(
          "target_month" => 9,
          "target_year" => 2026,
          "month_segment" => "late"
        ), message
      end
    end
  end

  it "normalizes natural month-segment answers" do
    examples = {
      "early" => [ "beginning of the month", "awal bulan", "月初" ],
      "mid" => [ "middle part", "pertengahan bulan", "月中" ],
      "late" => [ "last part", "hujung bulan", "akhir bulan", "月底", "月末" ]
    }

    examples.each do |segment, messages|
      messages.each do |message|
        result = described_class.new(
          message: message,
          slots: {},
          pending_question: "specific_timing",
          conversation_signals: signals,
          active_branch: { "target_month" => 9, "target_year" => 2026 }
        ).call

        expect(result["month_segment"]).to eq(segment), message
      end
    end
  end

  it "removes a model segment when the guest gives conflicting segments" do
    result = described_class.new(
      message: "early or end of the month",
      slots: { "target_month" => 9, "target_year" => 2026, "month_segment" => "late" },
      pending_question: "specific_timing",
      conversation_signals: signals,
      active_branch: { "target_month" => 9, "target_year" => 2026 }
    ).call

    expect(result).not_to include("month_segment")
  end

  it "removes a model segment from a bare relative month" do
    with_frozen_time Date.new(2026, 8, 28) do
      result = described_class.new(
        message: "next month",
        slots: { "target_month" => 9, "target_year" => 2026, "month_segment" => "late" },
        pending_question: "specific_timing",
        conversation_signals: signals
      ).call

      expect(result).to include("target_month" => 9, "target_year" => 2026, "month_segment" => "")
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

  # Frozen because the date on the branch has to be a date still to come:
  # a June the guest is standing in front of, not one they have walked past.
  it "extracts a specific date answer with an affirmative suffix" do
    with_frozen_time Date.new(2026, 6, 3) do
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
  end

  it "extracts a day-only answer from the active month context" do
    with_frozen_time Date.new(2026, 6, 3) do
      result = described_class.new(
        message: "23",
        slots: {},
        pending_question: "specific_timing",
        conversation_signals: signals,
        active_branch: { "target_month" => 6, "target_year" => 2026 }
      ).call

      expect(result["check_in"]).to eq("2026-06-23")
    end
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

  it "keeps a party size stated without a number when the model quotes the words that state it" do
    result = described_class.new(
      message: "me and my wife",
      slots: { "adults" => 2 },
      pending_question: "guest_count",
      conversation_signals: signals,
      evidence: { "party" => "me and my wife" }
    ).call

    expect(result["adults"]).to eq(2)
  end

  # The same question, the same shape of message, and the model quoting
  # nothing. Being asked used to be evidence in itself here -- the one rung
  # where a number the message never contained was believed, and the one rung
  # where believing it prices the stay wrong.
  it "drops a party size at the guest count question when the model quotes nothing" do
    result = described_class.new(
      message: "just a small one for the family",
      slots: { "adults" => 2 },
      pending_question: "guest_count",
      conversation_signals: signals
    ).call

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

  describe "a change of dates while a list is on screen" do
    # The guard this narrows was written when the number in a message about a
    # list was always a row. It is not: a guest looking at a catalogue is
    # exactly the guest who realises the dates are wrong.
    it "keeps dates the guest states while an option list is pending" do
      with_frozen_time Date.new(2026, 8, 20) do
        result = described_class.new(
          message: "actually 20 september to 22 september",
          slots: { "check_in" => "2026-09-20", "check_out" => "2026-09-22", "target_month" => 9, "target_year" => 2026 },
          pending_question: "select_option",
          conversation_signals: signals,
          evidence: { "timing" => "20 september", "checkout" => "22 september" },
          active_branch: { "suggested_options" => [ { "position" => 1 } ] }
        ).call

        expect(result).to include("check_in" => "2026-09-20", "check_out" => "2026-09-22")
      end
    end

    # And what the guard is for stays exactly as it was: a row is a row, and a
    # model quoting the digit as the words that say when they arrive does not
    # make it a date.
    it "still drops timing a bare row number was read as" do
      with_frozen_time Date.new(2026, 8, 20) do
        result = described_class.new(
          message: "2",
          slots: { "check_in" => "2026-09-02", "target_month" => 9, "target_year" => 2026 },
          pending_question: "confirm_selection",
          conversation_signals: signals,
          evidence: { "timing" => "2" }
        ).call

        expect(result).not_to include("check_in", "target_month")
      end
    end

    it "still drops timing quoted from a message about length of stay" do
      with_frozen_time Date.new(2026, 8, 20) do
        result = described_class.new(
          message: "3 nights",
          slots: { "check_in" => "2026-09-02", "target_month" => 9, "nights" => 3 },
          pending_question: "duration",
          conversation_signals: signals,
          evidence: { "timing" => "3 nights", "duration" => "3 nights" }
        ).call

        expect(result).not_to include("check_in", "target_month")
        expect(result["nights"]).to eq(3)
      end
    end
  end

  describe "a day the guest never named" do
    # The live thread this is taken from: a month, a length of stay, and a
    # first-of-the-month the model supplied to go with them. Read as a stated
    # date it is in the past, and the guest is told the month has gone.
    it "drops a model's arrival day when every number in the message is spent on something else" do
      with_frozen_time Date.new(2026, 8, 20) do
        result = described_class.new(
          message: "early august for 3 days 2 nights",
          slots: { "target_month" => 8, "target_year" => 2026, "month_segment" => "early", "check_in" => "2026-08-01", "nights" => 2 },
          pending_question: nil,
          conversation_signals: signals,
          evidence: { "timing" => "early august", "duration" => "3 days 2 nights" }
        ).call

        expect(result).not_to include("check_in")
        expect(result).to include("target_month" => 8, "month_segment" => "early")
      end
    end

    it "keeps a day named next to its month, and one written in ordinal" do
      with_frozen_time Date.new(2026, 8, 20) do
        named = described_class.new(
          message: "26 august for 3 days 2 nights",
          slots: { "check_in" => "2026-08-26", "nights" => 2 },
          pending_question: nil,
          conversation_signals: signals,
          evidence: { "timing" => "26 august" }
        ).call
        ordinal = described_class.new(
          message: "the 26th, 2 nights",
          slots: { "target_month" => 8, "target_year" => 2026, "check_in" => "2026-08-26", "nights" => 2 },
          pending_question: nil,
          conversation_signals: signals,
          evidence: { "timing" => "the 26th" }
        ).call

        expect(named["check_in"]).to eq("2026-08-26")
        expect(ordinal["check_in"]).to eq("2026-08-26")
      end
    end

    # The nouns that spend a number are English here and Malay and Chinese in
    # the guards below. A language missing from that list leaves its number
    # unexplained, which keeps the date -- the direction it has to fail in.
    it "keeps a day written in a language the counted nouns do not cover" do
      with_frozen_time Date.new(2026, 8, 20) do
        result = described_class.new(
          message: "28 tháng 8",
          slots: { "check_in" => "2026-08-28" },
          pending_question: nil,
          conversation_signals: signals,
          evidence: { "timing" => "28 tháng 8" }
        ).call

        expect(result["check_in"]).to eq("2026-08-28")
      end
    end

    it "drops a model's arrival day from a Chinese message about length of stay" do
      with_frozen_time Date.new(2026, 8, 20) do
        result = described_class.new(
          message: "住3晚",
          slots: { "target_month" => 8, "target_year" => 2026, "check_in" => "2026-08-01", "nights" => 3 },
          pending_question: nil,
          conversation_signals: signals,
          evidence: { "timing" => "住3晚", "duration" => "住3晚" }
        ).call

        expect(result).not_to include("check_in")
      end
    end

    # Same rule as the ranges this class parses itself, through the other door.
    it "rolls a model's past arrival day into the year still to come" do
      with_frozen_time Date.new(2026, 8, 20) do
        result = described_class.new(
          message: "3 januari hingga 5 januari",
          slots: { "target_month" => 1, "target_year" => 2026, "check_in" => "2026-01-03", "check_out" => "2026-01-05" },
          pending_question: nil,
          conversation_signals: signals,
          evidence: { "timing" => "3 januari", "checkout" => "5 januari" }
        ).call

        expect(result).to include("check_in" => "2027-01-03", "check_out" => "2027-01-05", "target_year" => 2027)
      end
    end

    it "leaves a past year the guest stated alone" do
      with_frozen_time Date.new(2026, 8, 20) do
        result = described_class.new(
          message: "3 januari 2026",
          slots: { "target_month" => 1, "target_year" => 2026, "check_in" => "2026-01-03" },
          pending_question: nil,
          conversation_signals: signals,
          evidence: { "timing" => "3 januari 2026" }
        ).call

        expect(result["check_in"]).to eq("2026-01-03")
      end
    end
  end

  # Frozen for the same reason as the specific-date examples above, and now for
  # one more: a date with no year in it that has been walked past rolls into
  # the year still to come, so an August assertion has to be made in August.
  it "keeps a date quoted in a language the English guards cannot read" do
    with_frozen_time Date.new(2026, 8, 20) do
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

  # Every example above could pass in any year. These cannot: the bug they
  # cover only exists in August looking at January, and it made every
  # cross-year enquiry -- the whole high season -- answer "no rooms available".
  describe "a year the guest did not say" do
    def normalize(message, pending_question: nil, slots: {})
      described_class.new(
        message: message,
        slots: slots,
        pending_question: pending_question,
        conversation_signals: signals
      ).call
    end

    it "reads a month already past this year as next year" do
      with_frozen_time Date.new(2026, 8, 20) do
        [ "3-5 january", "january 3-5", "3 jan to 5 jan" ].each do |message|
          result = normalize(message)

          expect(result["check_in"]).to eq("2027-01-03"), message
          expect(result["check_out"]).to eq("2027-01-05"), message
          expect(result["target_year"]).to eq(2027), message
        end
      end
    end

    it "reads days already past this month as next year" do
      with_frozen_time Date.new(2026, 8, 20) do
        expect(normalize("3-5 august")["check_in"]).to eq("2027-08-03")
      end
    end

    it "leaves dates still to come this year alone" do
      with_frozen_time Date.new(2026, 8, 20) do
        expect(normalize("25-27 august")["check_in"]).to eq("2026-08-25")
        expect(normalize("3-5 september")["check_in"]).to eq("2026-09-03")
      end
    end

    # A year the guest said is theirs, wrong or not. The ladder says so out
    # loud rather than moving it behind their back.
    it "does not move a year the guest stated" do
      with_frozen_time Date.new(2026, 8, 20) do
        expect(normalize("3-5 january 2026")["check_in"]).to eq("2026-01-03")
        expect(normalize("3-5 january 2027")["check_in"]).to eq("2027-01-03")
      end
    end

    it "still carries a stay across new year" do
      with_frozen_time Date.new(2026, 8, 20) do
        result = normalize("30 december to 2 january")

        expect(result["check_in"]).to eq("2026-12-30")
        expect(result["check_out"]).to eq("2027-01-02")
        expect(result["nights"]).to eq(3)
      end
    end

    it "reads a past date answering the specific timing question as next year" do
      with_frozen_time Date.new(2026, 8, 20) do
        expect(normalize("3 january", pending_question: "specific_timing")["check_in"]).to eq("2027-01-03")
      end
    end

    # The year on the branch was derived, not stated -- and may itself be a
    # year this bug wrote.
    it "rolls a past date built from the year already on the branch" do
      with_frozen_time Date.new(2026, 8, 20) do
        result = described_class.new(
          message: "the 3rd",
          slots: { "target_month" => 1, "target_year" => 2026 },
          pending_question: "specific_timing",
          conversation_signals: signals,
          active_branch: { "target_month" => 1, "target_year" => 2026 }
        ).call

        expect(result["check_in"]).to eq("2027-01-03")
      end
    end
  end
end
