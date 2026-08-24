# frozen_string_literal: true

module Concierge
  # The guest asks to be put through to a person.
  #
  # A request, not a handover. Flipping the thread to human here would be the
  # obvious move and the wrong one: it silences the assistant the instant the
  # guest asks, so an ask at 2am buys them nothing but silence until somebody
  # opens the inbox. The bot keeps answering; the thread simply appears on the
  # desk with the guest waiting on it, and a person takes it when they arrive.
  #
  # A thread staff already hold is left alone -- the person is already here.
  class RequestHumanAgent
    def initialize(conversation:)
      @conversation = conversation
    end

    def call
      return conversation if conversation.blank? || !conversation.open?
      return conversation if conversation.human? || conversation.human_requested?

      conversation.request_human!
      announce
      conversation
    end

    private

    attr_reader :conversation

    # In the transcript rather than only in the page furniture: whoever picks
    # the thread up should see that they were sent for, and when.
    def announce
      conversation.messages.create!(
        prospect: conversation.prospect,
        direction: "system",
        sender_role: "system",
        body: "You asked to speak to a team member. Someone will join shortly."
      )
    end
  end
end
