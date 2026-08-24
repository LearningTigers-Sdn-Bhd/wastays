# frozen_string_literal: true

require "rails_helper"

# The regression guard for the whole caching phase.
#
# Providers cache a prefix, so anything that changes per turn has to stay
# behind everything that does not. Nothing fails when that stops being true --
# the bot still answers, the suite still passes, the bill just goes back up.
# These two examples are what would notice.
RSpec.describe AiConcierge::Orchestration::AgentLoop::BuildInstructions do
  let(:hotel) { create(:hotel, :with_ai_concierge, name: "Villa Sereno") }
  let(:prospect) { create(:prospect, hotel: hotel) }
  let(:conversation_state) do
    create(:prospect_conversation_state, prospect: prospect, pending_question: "booking_timing")
  end

  def instructions(message: "hi")
    context = AiConcierge::Orchestration::AgentLoop::TurnContext.new(
      hotel: hotel, prospect: prospect, phone: nil,
      conversation_state: conversation_state, message: message
    )
    described_class.new(context: context)
  end

  it "keeps the turn out of the half that gets cached" do
    stable = instructions.stable

    expect(stable).to include("Villa Sereno")
    expect(stable).not_to include(Date.current.iso8601)
    expect(stable).not_to include("booking timing")
  end

  it "puts what changes every turn in the half that follows it" do
    volatile = instructions.volatile

    expect(volatile).to include(Date.current.iso8601)
    expect(volatile).to include("booking timing")
  end

  # Room types and knowledge languages belong to the hotel, not the turn, so
  # they are cacheable -- and they are the reason the stable half is big enough
  # to be worth caching at all.
  it "puts the hotel's own facts in the cached half" do
    create(:room_type, hotel: hotel, name: "Ocean Villa")

    expect(instructions.stable).to include("Ocean Villa")
  end
end
