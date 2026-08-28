# frozen_string_literal: true

module Concierge
  class BroadcastChatInput
    def self.call(conversation:)
      presenter = ChatInputPresenter.new(conversation: conversation)
      Turbo::StreamsChannel.broadcast_replace_to(
        [ conversation, :guest ],
        target: PublicUI::Chat::Panel::INPUT_REGION_ID,
        partial: "public/concierge/chats/input",
        locals: { hotel: conversation.hotel, input: presenter }
      )
    end
  end
end
