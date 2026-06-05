require "rails_helper"

RSpec.describe AiConcierge::Orchestration::Core::TransitionPolicy do
  let(:interpretation) do
    {
      "intent" => "booking_search",
      "conversation_signals" => {
        "is_reset" => false,
        "is_resume" => false,
        "is_correction" => false,
        "starts_new_booking_branch" => false,
        "end_conversation" => false
      }
    }
  end

  it "routes booking requests to booking" do
    result = described_class.new(
      interpretation: interpretation,
      active_branch: { "adults" => 2, "children" => 0 },
      paused_flows: [],
      pending_question: nil
    ).call

    expect(result[:action]).to eq(:booking)
  end

  it "routes month-window booking state to booking" do
    result = described_class.new(
      interpretation: interpretation,
      active_branch: { "target_month" => 8, "target_year" => 2026, "month_segment" => "early", "adults" => 2, "children" => 0 },
      paused_flows: [],
      pending_question: nil
    ).call

    expect(result[:action]).to eq(:booking)
  end

  it "routes check-in booking state to booking" do
    result = described_class.new(
      interpretation: interpretation,
      active_branch: { "check_in" => "2026-08-03", "adults" => 2, "children" => 0 },
      paused_flows: [],
      pending_question: nil
    ).call

    expect(result[:action]).to eq(:booking)
  end

  it "routes guest collection state to booking" do
    result = described_class.new(
      interpretation: interpretation,
      active_branch: { "target_month" => 8, "target_year" => 2026, "month_segment" => "early", "nights" => 2, "days" => 3 },
      paused_flows: [],
      pending_question: nil
    ).call

    expect(result[:action]).to eq(:booking)
  end

  it "routes adult-count collection state to booking" do
    result = described_class.new(
      interpretation: interpretation,
      active_branch: { "target_month" => 8, "target_year" => 2026, "month_segment" => "early", "nights" => 2, "days" => 3, "children" => 2 },
      paused_flows: [],
      pending_question: nil
    ).call

    expect(result[:action]).to eq(:booking)
  end

  it "routes party split collection state to booking" do
    result = described_class.new(
      interpretation: interpretation,
      active_branch: { "target_month" => 8, "target_year" => 2026, "month_segment" => "early", "nights" => 2, "days" => 3, "party_size_total" => 2 },
      paused_flows: [],
      pending_question: nil
    ).call

    expect(result[:action]).to eq(:booking)
  end

  it "routes unresolved party split state to booking" do
    result = described_class.new(
      interpretation: interpretation,
      active_branch: { "target_month" => 8, "target_year" => 2026, "month_segment" => "early", "nights" => 2, "days" => 3, "party_size_total" => 3, "adults" => 2, "children" => 0 },
      paused_flows: [],
      pending_question: nil
    ).call

    expect(result[:action]).to eq(:booking)
  end

  it "routes confirmation during party split to booking" do
    result = described_class.new(
      interpretation: { "intent" => "confirmation", "slots" => { "confirmation" => "yes" } },
      active_branch: { "party_size_total" => 4, "adults" => 2 },
      paused_flows: [],
      pending_question: "party_split"
    ).call

    expect(result[:action]).to eq(:booking)
  end

  it "routes resolved party split state to booking" do
    result = described_class.new(
      interpretation: { "intent" => "confirmation", "slots" => { "confirmation" => "yes" } },
      active_branch: { "party_size_total" => 4, "adults" => 2, "children" => 2 },
      paused_flows: [],
      pending_question: "party_split"
    ).call

    expect(result[:action]).to eq(:booking)
  end

  it "routes resolved booking state to booking" do
    result = described_class.new(
      interpretation: interpretation,
      active_branch: { "check_in" => "2026-08-03", "check_out" => "2026-08-05", "nights" => 2, "days" => 3, "adults" => 2, "children" => 0 },
      paused_flows: [],
      pending_question: nil
    ).call

    expect(result[:action]).to eq(:booking)
  end

  it "resumes paused option selections before validating them" do
    result = described_class.new(
      interpretation: interpretation.merge("intent" => "option_selection"),
      active_branch: {},
      paused_flows: [ { "topic" => "booking_search" } ],
      pending_question: nil,
      message: "option 2"
    ).call

    expect(result[:action]).to eq(:resume)
  end

  it "resumes suspended confirmation before handling yes or no" do
    result = described_class.new(
      interpretation: interpretation.merge("intent" => "confirmation", "slots" => { "confirmation" => "yes" }),
      active_branch: {},
      booking_task: { "status" => "suspended", "suspended" => true, "pending_question" => "confirm_selection" },
      pending_question: nil,
      message: "yes"
    ).call

    expect(result[:action]).to eq(:resume)
  end

  it "does not resume suspended bookings for hotel policy questions" do
    result = described_class.new(
      interpretation: interpretation.merge("intent" => "hotel_policy", "topic" => "hotel_policy"),
      active_branch: {},
      booking_task: {
        "status" => "suspended",
        "suspended" => true,
        "pending_question" => "specific_timing",
        "branch" => { "target_month" => 6, "target_year" => 2026, "month_segment" => "early" }
      },
      pending_question: nil,
      message: "what should i aware during booking in this hotel?"
    ).call

    expect(result[:action]).to eq(:librarian)
    expect(result[:pause]).to be(false)
  end

  it "does not resume expired suspended bookings" do
    result = described_class.new(
      interpretation: interpretation.merge("intent" => "confirmation", "slots" => { "confirmation" => "yes" }),
      active_branch: {},
      booking_task: {
        "status" => "expired",
        "suspended" => true,
        "pending_question" => "confirm_selection",
        "expires_at" => 1.hour.ago.iso8601
      },
      pending_question: nil,
      message: "yes"
    ).call

    expect(result[:action]).to eq(:booking)
  end

  it "resumes a suspended v2 booking when a shown room type is mentioned" do
    result = described_class.new(
      interpretation: interpretation,
      active_branch: {},
      booking_task: {
        "status" => "suspended",
        "suspended" => true,
        "pending_question" => "select_option",
        "branch" => {
          "suggested_options" => [
            { "room_type_name" => "Executive Penthouse", "options" => [] }
          ]
        }
      },
      pending_question: nil,
      message: "i want the executive"
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

  it "resumes a suspended slot-collection flow when the user returns with a booking date" do
    result = described_class.new(
      interpretation: interpretation.merge("intent" => "confirmation", "slots" => { "confirmation" => "yes" }),
      active_branch: {},
      booking_task: {
        "status" => "suspended",
        "suspended" => true,
        "pending_question" => "specific_timing",
        "branch" => { "target_month" => 6, "target_year" => 2026 }
      },
      pending_question: nil,
      message: "ok, i want to book on 23 june"
    ).call

    expect(result[:action]).to eq(:resume)
  end

  it "resumes a suspended duration question when the user returns with stay length" do
    result = described_class.new(
      interpretation: interpretation.merge("intent" => "booking_search", "slots" => { "nights" => 2 }),
      active_branch: {},
      booking_task: {
        "status" => "suspended",
        "suspended" => true,
        "pending_question" => "duration",
        "branch" => { "check_in" => "2026-06-23" }
      },
      pending_question: nil,
      message: "2 nights"
    ).call

    expect(result[:action]).to eq(:resume)
  end

  it "ends the current conversation before other transitions" do
    result = described_class.new(
      interpretation: interpretation.deep_merge("conversation_signals" => { "end_conversation" => true }),
      active_branch: { "target_month" => 8 },
      paused_flows: [],
      pending_question: nil
    ).call

    expect(result[:action]).to eq(:end_conversation)
  end

  it "routes information intents to librarian with pause metadata" do
    result = described_class.new(
      interpretation: interpretation.merge("intent" => "hotel_information"),
      active_branch: { "target_month" => 8 },
      paused_flows: [],
      pending_question: "duration"
    ).call

    expect(result[:action]).to eq(:librarian)
    expect(result[:pause]).to eq(true)
  end

  it "pauses exact-date booking flows for information intents" do
    result = described_class.new(
      interpretation: interpretation.merge("intent" => "hotel_information"),
      active_branch: { "check_in" => "2026-06-23" },
      paused_flows: [],
      pending_question: "duration"
    ).call

    expect(result[:action]).to eq(:librarian)
    expect(result[:pause]).to eq(true)
  end

  it "routes booking context separately" do
    result = described_class.new(
      interpretation: interpretation.merge("intent" => "booking_context"),
      active_branch: {},
      paused_flows: [],
      pending_question: nil
    ).call

    expect(result[:action]).to eq(:booking_context)
  end

  it "routes greetings separately" do
    result = described_class.new(
      interpretation: interpretation.merge("intent" => "greeting"),
      active_branch: {},
      paused_flows: [],
      pending_question: nil
    ).call

    expect(result[:action]).to eq(:greeting)
  end

  it "routes pending booking follow-ups to booking before greeting" do
    result = described_class.new(
      interpretation: interpretation.merge("intent" => "greeting"),
      active_branch: { "suggested_options" => [ { "room_type_name" => "Executive Penthouse", "options" => [] } ] },
      paused_flows: [],
      pending_question: "select_option",
      message: "executive"
    ).call

    expect(result[:action]).to eq(:booking)
  end

  it "routes information intents during option selection to librarian instead of selecting an option" do
    result = described_class.new(
      interpretation: interpretation.merge("intent" => "room_information", "topic" => "room_information"),
      active_branch: { "target_month" => 8, "suggested_options" => [ { "room_type_name" => "Executive Penthouse", "options" => [] } ] },
      paused_flows: [],
      pending_question: "select_option",
      message: "what amenities does executive penthouse have?"
    ).call

    expect(result[:action]).to eq(:librarian)
    expect(result[:pause]).to eq(true)
  end

  it "routes hotel amenities after completed booking to librarian" do
    result = described_class.new(
      interpretation: interpretation.merge("intent" => "hotel_information", "topic" => "general_hotel_info"),
      active_branch: {},
      paused_flows: [],
      booking_task: { "status" => "completed", "pending_question" => nil },
      pending_question: nil,
      message: "may i know hotel amenities"
    ).call

    expect(result[:action]).to eq(:librarian)
    expect(result[:pause]).to eq(false)
  end

  it "falls back for unknown intents without booking state" do
    result = described_class.new(
      interpretation: interpretation.merge("intent" => "unknown"),
      active_branch: {},
      paused_flows: [],
      pending_question: nil
    ).call

    expect(result[:action]).to eq(:fallback)
  end
end
