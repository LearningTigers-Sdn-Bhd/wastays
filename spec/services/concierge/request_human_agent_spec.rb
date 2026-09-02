# frozen_string_literal: true

require "rails_helper"

RSpec.describe Concierge::RequestHumanAgent do
  let(:hotel) { create(:hotel) }
  let(:prospect) { create(:prospect, hotel: hotel) }
  let(:conversation) { create(:conversation, hotel: hotel, prospect: prospect, channel: "web") }

  it "puts the guest in front of staff" do
    described_class.new(conversation: conversation).call

    expect(conversation.reload).to be_human_requested
    expect(Conversation.awaiting_staff).to include(conversation)
  end

  # The whole point of the flag existing instead of a mode flip: an ask at 2am
  # must not buy the guest silence until somebody opens the inbox.
  it "leaves the assistant answering while they wait" do
    described_class.new(conversation: conversation).call

    expect(conversation.reload).to be_bot
  end

  it "tells the guest, and whoever picks the thread up, in the transcript" do
    described_class.new(conversation: conversation).call

    expect(conversation.messages.last.sender_role).to eq("system")
    expect(conversation.messages.last.body).to include("asked to speak to a team member")
  end

  it "uses the approved support reply for booking support" do
    described_class.new(conversation: conversation, reason: :booking_support).call

    message = conversation.messages.last
    expect(message.sender_role).to eq("bot")
    expect(message.body).to include("I have asked the hotel team", "continue chatting while you wait")
    expect(prospect.prospect_conversation_state.slots_payload.dig("ui_task", "suggestion_group")).to eq("staff_wait")
  end

  it "adds the booking-support reply once without restarting an existing staff wait" do
    described_class.new(conversation: conversation).call
    first_asked_at = conversation.reload.human_requested_at

    expect {
      2.times { described_class.new(conversation: conversation, reason: :booking_support).call }
    }.to change { conversation.messages.where(sender_role: "bot").count }.by(1)

    expect(conversation.reload.human_requested_at).to eq(first_asked_at)
    expect(conversation.messages.last.body).to include("I have asked the hotel team")
  end

  # Asked twice is still asked once: the first ask is what says how long they
  # have been waiting.
  it "does not restart the wait when the guest asks again" do
    described_class.new(conversation: conversation).call
    first_asked_at = conversation.reload.human_requested_at

    expect {
      described_class.new(conversation: conversation).call
    }.not_to change(ProspectMessage, :count)

    expect(conversation.reload.human_requested_at).to eq(first_asked_at)
  end

  it "leaves a thread a person already holds alone" do
    conversation.hand_to_human!

    described_class.new(conversation: conversation).call

    expect(conversation.reload).not_to be_human_requested
  end

  it "shrugs at a visitor with no thread at all" do
    expect { described_class.new(conversation: nil).call }.not_to raise_error
  end

  # The request is a call for someone. It stops meaning anything the moment
  # somebody answers it.
  it "is cleared when a person actually takes the thread" do
    staff = create(:user, account: hotel.account, name: "Farah Idris")
    described_class.new(conversation: conversation).call

    Concierge::TakeOverConversation.new(conversation: conversation, user: staff).call

    expect(conversation.reload).not_to be_human_requested
  end
end
