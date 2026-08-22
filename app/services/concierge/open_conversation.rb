# frozen_string_literal: true

module Concierge
  # The thread a guest's next message belongs to.
  #
  # One open thread per person per channel: the one they are still in gets
  # continued, and anything already closed means this message starts a new one.
  #
  # Replacing a closed thread starts the assistant over. Its state is keyed to
  # the prospect rather than to the thread, so it outlives every chat the guest
  # clears -- and left standing, the question the closed thread was waiting on
  # ("which option?") is still open, and the first "hello" of the fresh chat is
  # read as an answer to it.
  #
  # Only when there was a thread to replace: a guest's first message has no
  # earlier thread to inherit from, and a state already sitting there belongs
  # to whoever put it there.
  class OpenConversation
    def initialize(prospect:, channel:)
      @prospect = prospect
      @channel = channel
    end

    def call
      existing = prospect.conversations.open.find_by(channel: channel)
      return existing if existing

      replacing_closed_thread = prospect.conversations.where(channel: channel).exists?
      prospect.conversations.create!(hotel: prospect.hotel, channel: channel).tap do
        reset_state! if replacing_closed_thread
      end
    end

    private

    attr_reader :prospect, :channel

    def reset_state!
      state = prospect.prospect_conversation_state || ProspectConversationState.create_or_find_by!(prospect: prospect)
      state.reset!
    end
  end
end
