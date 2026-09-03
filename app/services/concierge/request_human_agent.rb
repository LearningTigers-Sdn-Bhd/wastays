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
    BOOKING_SUPPORT_REASON = "booking_support"

    def initialize(conversation:, reason: nil)
      @conversation = conversation
      @reason = reason.to_s == BOOKING_SUPPORT_REASON ? BOOKING_SUPPORT_REASON : nil
    end

    def call
      return conversation if conversation.blank? || !conversation.open?
      return conversation if conversation.human?
      if conversation.human_requested?
        record_booking_support_message if booking_support? && !booking_support_announced?
        return conversation
      end

      conversation.request_human!
      announce
      conversation
    end

    private

    attr_reader :conversation, :reason

    def booking_support? = reason == BOOKING_SUPPORT_REASON

    # In the transcript rather than only in the page furniture: whoever picks
    # the thread up should see that they were sent for, and when.
    def announce
      if booking_support?
        record_booking_support_message
      else
        record_generic_message
      end
    end

    def record_booking_support_message
      state = conversation.prospect.prospect_conversation_state ||
        ProspectConversationState.create_or_find_by!(prospect: conversation.prospect)
      manager = AiConcierge::State::ConversationTaskManager.new(slots_payload: state.slots_payload)
      state.update!(slots_payload: manager.record_booking_support_requested)

      conversation.messages.create!(
        prospect: conversation.prospect,
        direction: "outbound",
        sender_role: "bot",
        body: booking_support_message
      )
    end

    def booking_support_announced?
      conversation.messages.where(
        direction: "outbound",
        sender_role: "bot",
        body: booking_support_message
      ).exists?
    end

    def booking_support_message
      @booking_support_message ||= AiConcierge::MessageBuilders::ExistingBookingBuilder.new(
        hotel: conversation.hotel,
        context: {}
      ).call(:booking_support_requested)
    end

    def record_generic_message
      conversation.messages.create!(
        prospect: conversation.prospect,
        direction: "system",
        sender_role: "system",
        body: "You asked to speak to a team member. Someone will join shortly."
      )
    end
  end
end
