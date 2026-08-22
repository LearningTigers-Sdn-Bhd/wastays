# frozen_string_literal: true

module Concierge
  # A person takes the thread off the bot.
  #
  # One move, not two: the bot stops answering and the thread gains an owner at
  # the same moment, because a thread nobody owns that the bot is no longer
  # answering is a guest waiting on silence.
  #
  # Already-human threads are left exactly as they are -- the second staff
  # member to reply does not quietly steal the thread from the first.
  class TakeOverConversation
    def initialize(conversation:, user: nil)
      @conversation = conversation
      @user = user
    end

    def call
      return conversation unless conversation.bot?

      conversation.hand_to_human!(user: user)
      announce
      conversation
    end

    private

    attr_reader :conversation, :user

    # The guest is told, and told in the transcript rather than only in the
    # page furniture: months later the thread should still show where the bot
    # stopped and a person started.
    def announce
      conversation.messages.create!(
        prospect: conversation.prospect,
        direction: "system",
        sender_role: "system",
        body: announcement
      )
    end

    def announcement
      name = user&.name.presence
      return "A team member has joined this conversation." if name.blank?

      "#{name} from the front desk has joined this conversation."
    end
  end
end
