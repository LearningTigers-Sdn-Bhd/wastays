# frozen_string_literal: true

require "rails_helper"

RSpec.describe Concierge::ClearConversation do
  let(:hotel) { create(:hotel) }
  let(:prospect) { create(:prospect, hotel: hotel) }
  let(:conversation) { create(:conversation, hotel: hotel, prospect: prospect, channel: "web") }

  it "puts the thread away without erasing what was said" do
    conversation.messages.create!(prospect: prospect, direction: "inbound", sender_role: "guest", body: "Do you have parking?")

    described_class.new(conversation: conversation).call

    expect(conversation.reload).not_to be_open
    expect(conversation.messages.where(body: "Do you have parking?")).to exist
  end

  # Staff reading the thread later should be able to see why it stops.
  it "says in the transcript why the thread ends" do
    described_class.new(conversation: conversation).call

    expect(conversation.messages.last.sender_role).to eq("system")
    expect(conversation.messages.last.body).to include("cleared this conversation")
  end

  # Only one open thread per person per channel is allowed, so closing this one
  # is what lets the next message start a fresh one.
  it "leaves room for the guest's next message to open a new thread" do
    described_class.new(conversation: conversation).call

    expect {
      prospect.conversations.create!(hotel: hotel, channel: "web")
    }.to change(Conversation, :count).by(1)
  end

  it "does nothing to a thread that is already closed" do
    conversation.close!

    expect {
      described_class.new(conversation: conversation.reload).call
    }.not_to change(ProspectMessage, :count)
  end

  # A visitor who has never written has nothing to clear, and should not have to
  # be told apart from one who has.
  it "shrugs at a visitor with no thread at all" do
    expect { described_class.new(conversation: nil).call }.not_to raise_error
  end
end
