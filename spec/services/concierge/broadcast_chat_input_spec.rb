# frozen_string_literal: true

require "rails_helper"

RSpec.describe Concierge::BroadcastChatInput do
  it "replaces the guest input region with the current presenter" do
    conversation = create(:conversation, channel: "web")
    presenter = instance_double(Concierge::ChatInputPresenter)
    allow(Concierge::ChatInputPresenter).to receive(:new).with(conversation: conversation).and_return(presenter)

    expect(Turbo::StreamsChannel).to receive(:broadcast_replace_to).with(
      [ conversation, :guest ],
      target: PublicUI::Chat::Panel::INPUT_REGION_ID,
      partial: "public/concierge/chats/input",
      locals: { hotel: conversation.hotel, input: presenter }
    )

    described_class.call(conversation: conversation)
  end
end
