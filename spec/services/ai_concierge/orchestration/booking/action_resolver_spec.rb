require "rails_helper"

RSpec.describe AiConcierge::Orchestration::Booking::ActionResolver do
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

  it "asks for month clarification while a date range month is pending" do
    action = described_class.new(
      interpretation: interpretation(intent: "booking_search", slots: {}),
      active_branch: { "clarification_needed" => { "type" => "date_range_month", "start_day" => 16, "end_day" => 18 } },
      pending_question: "booking_timing"
    ).call

    expect(action).to eq(:ask_date_range_month)
  end

  it "does not let stale date range clarification override completed timing" do
    action = described_class.new(
      interpretation: interpretation(intent: "booking_search", slots: {}),
      active_branch: branch_with_required_booking_slots.merge("clarification_needed" => { "type" => "date_range_month", "start_day" => 16, "end_day" => 18 }),
      pending_question: "booking_timing"
    ).call

    expect(action).to eq(:search_options)
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

  it "selects an option while a suggested list is on the table" do
    action = described_class.new(
      interpretation: interpretation(intent: "option_selection", slots: { "option_number" => "1" }),
      active_branch: branch_with_required_booking_slots.merge("suggested_options" => [ { "room_type_name" => "Ocean Villa King", "options" => [ { "selection_id" => "a" } ] } ]),
      pending_question: "select_option"
    ).call

    expect(action).to eq(:option_selection)
  end

  it "does not read a turn as an option selection when no options were shown" do
    action = described_class.new(
      interpretation: interpretation(intent: "option_selection", slots: {}),
      active_branch: {},
      pending_question: "select_option"
    ).call

    expect(action).to eq(:ask_booking_timing)
  end

  it "searches options when required booking slots are complete" do
    action = described_class.new(
      interpretation: interpretation(intent: "booking_search", slots: {}),
      active_branch: branch_with_required_booking_slots,
      pending_question: nil
    ).call

    expect(action).to eq(:search_options)
  end

  # A "yes" the model did not pass along used to fall past every question in
  # the ladder and land on a fresh search, which showed the guest the catalogue
  # they had already chosen from.
  it "asks the confirmation again when the answer to it could not be read" do
    action = described_class.new(
      interpretation: interpretation(intent: "booking_search", slots: {}),
      active_branch: branch_with_required_booking_slots.merge("confirmation_candidate" => { "room_type_name" => "Deluxe Room" }),
      pending_question: "confirm_selection"
    ).call

    expect(action).to eq(:ask_confirmation)
  end

  # A turn that really changes the search has already cleared the candidate by
  # the time this runs -- that is what SlotMerger does with a changed party --
  # so an empty branch here is what a real change looks like.
  it "still searches when the turn really changes the search" do
    action = described_class.new(
      interpretation: interpretation(intent: "booking_search", slots: { "adults" => 4 }),
      active_branch: branch_with_required_booking_slots,
      pending_question: "confirm_selection"
    ).call

    expect(action).to eq(:search_options)
  end

  # The candidate a rate plan was just applied to lives in `selected_option`
  # too, and a confirmation asked about it must be askable again.
  it "asks the confirmation again when only the selected option is on the branch" do
    action = described_class.new(
      interpretation: interpretation(intent: "booking_search", slots: {}),
      active_branch: branch_with_required_booking_slots.merge("selected_option" => { "room_type_name" => "Deluxe Room" }),
      pending_question: "confirm_selection"
    ).call

    expect(action).to eq(:ask_confirmation)
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
