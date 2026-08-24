# frozen_string_literal: true

require "rails_helper"

RSpec.describe Concierge::ReturnConversationToBot do
  let(:hotel) { create(:hotel) }
  let(:user) { create(:user, account: hotel.account) }
  let(:prospect) { create(:prospect, hotel: hotel) }
  let(:conversation) { create(:conversation, hotel: hotel, prospect: prospect, mode: "human", assigned_user: user) }

  it "hands the thread back and lets it go" do
    described_class.new(conversation: conversation).call

    expect(conversation.reload).to be_bot
    expect(conversation.assigned_user).to be_nil
  end

  it "tells the guest who they are talking to now" do
    described_class.new(conversation: conversation).call

    expect(conversation.messages.reload.last.body).to eq("Our assistant is answering again.")
  end

  it "does nothing to a thread the bot already has" do
    bot_thread = create(:conversation, hotel: hotel, prospect: create(:prospect, hotel: hotel))

    expect { described_class.new(conversation: bot_thread).call }
      .not_to change { bot_thread.messages.count }
  end
end
