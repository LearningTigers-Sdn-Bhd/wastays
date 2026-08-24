# frozen_string_literal: true

module Concierge
  # The guest puts their conversation away.
  #
  # Closed rather than deleted, and deliberately so: the hotel keeps what was
  # said, and the guest keeps the same identity, so a thread they clear on
  # Monday and one they start on Thursday are still the same person to whoever
  # is reading the inbox. What they get is an empty chat, not an erased one --
  # anything else would be a promise the app cannot keep.
  #
  # Closing is also what makes room for the next thread: only one open
  # conversation per person per channel is allowed, so the guest's next message
  # opens a fresh one on its own.
  class ClearConversation
    def initialize(conversation:)
      @conversation = conversation
    end

    def call
      return conversation if conversation.blank? || !conversation.open?

      announce
      conversation.close!
      conversation
    end

    private

    attr_reader :conversation

    # Said in the transcript rather than only in the log: staff reading the
    # thread later should be able to see why it stops mid-sentence.
    def announce
      conversation.messages.create!(
        prospect: conversation.prospect,
        direction: "system",
        sender_role: "system",
        body: "The guest cleared this conversation."
      )
    end
  end
end
