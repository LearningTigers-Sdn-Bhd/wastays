# frozen_string_literal: true

require "rails_helper"

RSpec.describe Concierge::CloseStaleConversationsJob do
  # Nothing arrives on a thread that has gone quiet, so nothing would ever
  # trigger a check made on the next message. It has to be swept.
  it "runs the sweep" do
    sweep = instance_double(Concierge::CloseStaleConversations, call: 0)
    allow(Concierge::CloseStaleConversations).to receive(:new).and_return(sweep)

    described_class.perform_now

    expect(sweep).to have_received(:call)
  end

  it "closes a thread nobody has said anything on for days" do
    hotel = create(:hotel)
    prospect = create(:prospect, hotel: hotel)
    conversation = create(:conversation, hotel: hotel, prospect: prospect)
    create(:prospect_message, conversation: conversation, prospect: prospect)
    conversation.update_columns(last_message_at: Concierge::CloseStaleConversations::STALE_AFTER.ago - 1.hour)

    described_class.perform_now

    expect(conversation.reload).not_to be_open
  end
end
