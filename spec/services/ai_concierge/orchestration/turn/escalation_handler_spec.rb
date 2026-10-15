# frozen_string_literal: true

require "rails_helper"

RSpec.describe AiConcierge::Orchestration::Turn::EscalationHandler do
  let(:hotel) { create(:hotel) }
  let(:prospect) { create(:prospect, hotel: hotel) }
  let(:conversation) { create(:conversation, hotel: hotel, prospect: prospect) }
  let(:state) { create(:prospect_conversation_state, prospect: prospect) }

  def handle(message)
    described_class.new(hotel: hotel, conversation: conversation, message: message)
      .call(conversation_state: state)
  end

  it "does not intercept a message without an escalation trigger" do
    expect(handle("What time is breakfast?")).to be_nil
  end

  it "does not request another handoff after staff have been requested" do
    conversation.request_human!

    expect(handle("I need to speak to a manager")).to be_nil
  end

  it "builds a front-desk handoff for an explicit staff request" do
    result = handle("I need to speak to a manager")

    expect(result.slots_payload).to eq(state.slots_payload)
    expect(result.next_action.kind).to eq("offer_front_desk")
    expect(result.needs_human_support).to be(true)
    expect(result.extra_context).to include(
      escalation_trigger: "guest_asks_for_person",
      message: include("asked a team member")
    )
  end
end
