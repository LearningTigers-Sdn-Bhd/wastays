# frozen_string_literal: true

require "rails_helper"

RSpec.describe Concierge::TakeOverConversation do
  let(:hotel) { create(:hotel) }
  let(:user) { create(:user, account: hotel.account, name: "Farah Idris") }
  let(:prospect) { create(:prospect, hotel: hotel) }
  let(:conversation) { create(:conversation, hotel: hotel, prospect: prospect) }

  it "stops the bot and gives the thread an owner in one move" do
    described_class.new(conversation: conversation, user: user).call

    expect(conversation.reload).to be_human
    expect(conversation.assigned_user).to eq(user)
  end

  it "writes the handover into the transcript the guest can read" do
    described_class.new(conversation: conversation, user: user).call

    system_message = conversation.messages.reload.last
    expect(system_message.sender_role).to eq("system")
    expect(system_message.body).to include("Farah Idris")
  end

  it "names nobody in particular when nobody in particular took it" do
    described_class.new(conversation: conversation).call

    expect(conversation.messages.reload.last.body).to eq("A team member has joined this conversation.")
  end

  # The second person to reply is helping, not taking the thread off the first.
  it "leaves a thread a colleague is already holding alone" do
    described_class.new(conversation: conversation, user: user).call
    colleague = create(:user, account: hotel.account, name: "Zul Hakim")

    expect {
      described_class.new(conversation: conversation, user: colleague).call
    }.not_to change { conversation.reload.assigned_user }

    expect(conversation.messages.reload.count).to eq(1)
  end
end
