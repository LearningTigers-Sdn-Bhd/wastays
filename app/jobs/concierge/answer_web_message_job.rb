# frozen_string_literal: true

module Concierge
  # The assistant's answer to a message the guest has already sent.
  #
  # Out of the request on purpose. Waiting on a model is seconds, and a guest
  # who has pressed Send should see their own words immediately rather than a
  # frozen page -- so the message is filed first and this catches up. The answer
  # reaches the page down the stream the guest is already subscribed to, so
  # nothing here has to know how it gets there.
  #
  # Whether the assistant should still speak is decided here rather than by the
  # caller: staff can take the thread over between the guest pressing Send and
  # this running, and a bot answer landing on top of a person's is the one thing
  # the mode column exists to prevent.
  class AnswerWebMessageJob < ApplicationJob
    queue_as :default

    UNAVAILABLE_NOTICE = "Our assistant could not answer that one. The front desk has your message and will reply here."

    def perform(conversation_id, message)
      conversation = Conversation.includes(:hotel, :prospect).find_by(id: conversation_id)
      return if conversation.blank?
      return unless conversation.hotel.ai_concierge_ready?
      return unless conversation.bot? && conversation.open?

      result = ask(conversation, message)
      return if result.success?

      note_failure(conversation)
    end

    private

    def ask(conversation, message)
      AiConcierge::Orchestration::Core::InquiryResponder.new(
        hotel: conversation.hotel,
        message: message,
        prospect_public_id: conversation.prospect.public_id,
        channel: conversation.channel,
        record_inbound: false
      ).call
    end

    # Silence would read as the hotel ignoring them. The line is filed as a
    # message so it reaches the guest down the stream they are already on, and
    # shows up in the inbox too -- staff should be able to see that the guest
    # was left waiting.
    def note_failure(conversation)
      conversation.messages.create!(
        prospect: conversation.prospect,
        direction: "system",
        sender_role: "system",
        body: UNAVAILABLE_NOTICE
      )
    end
  end
end
