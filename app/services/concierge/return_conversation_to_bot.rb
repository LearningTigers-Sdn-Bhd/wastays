# frozen_string_literal: true

module Concierge
  # Staff hand the thread back to the assistant.
  #
  # Only offered where there is an assistant to hand it back to; a hotel with
  # the AI switched off would be handing the guest to nobody.
  class ReturnConversationToBot
    def initialize(conversation:)
      @conversation = conversation
    end

    def call
      return conversation unless conversation.human?

      conversation.return_to_bot!
      announce
      conversation
    end

    private

    attr_reader :conversation

    def announce
      conversation.messages.create!(
        prospect: conversation.prospect,
        direction: "system",
        sender_role: "system",
        body: "Our assistant is answering again."
      )
    end
  end
end
