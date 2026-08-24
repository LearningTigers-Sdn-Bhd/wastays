# frozen_string_literal: true

module Concierge
  # Handing a staff reply to whatever can actually put it on WhatsApp.
  #
  # The app has no WhatsApp connection of its own -- no credentials, no client,
  # nothing. Every WhatsApp message it has ever "sent" was a webhook to an
  # outside relay that owns the business account and does the sending. A staff
  # reply is the same trip with a new event name on it.
  #
  # Nothing happens for the web chat: the guest's browser is already subscribed
  # to the thread and had the reply before this ran.
  class DeliverStaffReply
    EVENT = "concierge_staff_reply"

    def self.call(message:) = new(message: message).call

    def initialize(message:)
      @message = message
    end

    def call
      return unless message.from_staff?
      return unless conversation&.channel == "whatsapp"
      return unless conversation.replies_reach_guest?

      WebhookBroadcastJob.perform_later(EVENT, payload, hotel_id: conversation.hotel_id)
    end

    private

    attr_reader :message

    def conversation = message.conversation
    def prospect = message.prospect
    def hotel = conversation.hotel

    # `message_id` is the point of this payload as much as the body is: a
    # delivery that is retried arrives twice, and the relay needs something
    # stable to recognise the second one by.
    #
    # The hotel's own number travels too, because a relay serving several
    # hotels has to know which of its numbers to send from.
    def payload
      {
        message_id: message.id,
        conversation_id: conversation.id,
        hotel_name: hotel.name,
        hotel_whatsapp_number: hotel.whatsapp_number,
        guest_name: prospect.name,
        guest_phone: prospect.phone_number,
        staff_name: message.sender_user&.name,
        body: message.body,
        sent_at: message.sent_at&.iso8601
      }
    end
  end
end
