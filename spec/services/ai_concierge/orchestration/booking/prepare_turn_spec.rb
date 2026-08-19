# frozen_string_literal: true

require "rails_helper"

RSpec.describe AiConcierge::Orchestration::Booking::PrepareTurn do
  let(:hotel) { create(:hotel, :with_ai_concierge) }
  let(:prospect) { create(:prospect, hotel: hotel) }

  def interpretation(slots: {}, signals: {})
    {
      "intent" => "booking_search",
      "slots" => slots,
      "conversation_signals" => {
        "is_reset" => false, "is_resume" => false, "is_correction" => false,
        "starts_new_booking_branch" => false, "end_conversation" => false
      }.merge(signals)
    }
  end

  def prepare(state, message:, slots: {}, signals: {})
    described_class.new(
      conversation_state: state,
      interpretation: interpretation(slots: slots, signals: signals),
      message: message
    ).call
  end

  # The invariant the rewrite must not break: what the guest said five messages
  # ago is in Postgres, not in a context window, and this turn only adds to it.
  it "merges what this message says into the booking already in progress" do
    state = create(:prospect_conversation_state, :awaiting_guest_count, prospect: prospect)

    prepared = prepare(state, message: "2 adults", slots: { "adults" => 2 })

    expect(prepared.active_branch).to include("adults" => 2, "target_month" => 8, "nights" => 2)
    expect(prepared.pending_question).to eq("guest_count")
  end

  it "carries dates the guest did not repeat" do
    state = create(:prospect_conversation_state, :awaiting_option_selection, prospect: prospect)

    prepared = prepare(state, message: "option 1", slots: { "option_number" => "1" })

    expect(prepared.active_branch["target_month"]).to eq(8)
    expect(prepared.pending_question).to eq("select_option")
  end

  # A guest asking for a second, separate booking starts from nothing rather
  # than inheriting last month's dates.
  it "puts the finished booking away when a new one starts" do
    state = create(:prospect_conversation_state, :awaiting_option_selection, prospect: prospect)

    prepared = prepare(state, message: "another booking please", signals: { "starts_new_booking_branch" => true })

    expect(prepared.active_branch["target_month"]).to be_nil
    expect(prepared.pending_question).to be_nil
  end

  it "adopts a pending question the thread recorded outside the booking task" do
    state = create(:prospect_conversation_state, prospect: prospect, pending_question: "guest_count")

    expect(prepare(state, message: "2 adults", slots: { "adults" => 2 }).pending_question).to eq("guest_count")
  end
end
