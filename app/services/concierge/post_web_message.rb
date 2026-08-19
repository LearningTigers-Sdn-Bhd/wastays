# frozen_string_literal: true

module Concierge
  # A message typed into the chat on the public concierge page.
  #
  # The bot answering is an enhancement, not the mechanism. A hotel with no AI
  # provider configured still gets a working message desk: the guest writes, the
  # thread appears in the portal inbox, and a person answers. The same is true
  # once staff take a thread over -- the bot goes quiet and the message is
  # simply filed.
  class PostWebMessage
    CHANNEL = "web"
    MAX_MESSAGE_LENGTH = 2_000

    Result = Struct.new(:prospect, :conversation, :error, keyword_init: true) do
      def success? = error.blank?
    end

    def initialize(hotel:, message:, prospect_public_id: nil)
      @hotel = hotel
      @message = message.to_s.strip
      @prospect_public_id = prospect_public_id.to_s.strip.presence
    end

    def call
      return Result.new(error: "Please type a message first.") if message.blank?
      return Result.new(error: "That message is too long.") if message.length > MAX_MESSAGE_LENGTH

      prospect = resolve_prospect
      conversation = resolve_conversation(prospect)

      error = bot_answers?(conversation) ? ask_the_bot(prospect) : record_only(prospect, conversation)

      Result.new(prospect: prospect, conversation: conversation.reload, error: error)
    end

    private

    attr_reader :hotel, :message, :prospect_public_id

    # A visitor who has not said who they are yet is still a person worth
    # keeping: the prospect carries the thread, and public_id is how the
    # browser finds its way back to it.
    def resolve_prospect
      existing = hotel.prospects.find_by(public_id: prospect_public_id) if prospect_public_id
      existing || hotel.prospects.create!(phone_number: nil)
    end

    def resolve_conversation(prospect)
      prospect.conversations.open.find_by(channel: CHANNEL) ||
        prospect.conversations.create!(hotel: hotel, channel: CHANNEL)
    end

    def bot_answers?(conversation)
      hotel.ai_concierge_ready? && conversation.bot?
    end

    # The orchestrator records the guest's message itself as it loads the
    # session, so a failure here means the message is already filed and only
    # the reply is missing -- which is exactly what should be reported.
    def ask_the_bot(prospect)
      result = AiConcierge::Orchestration::Core::InquiryResponder.new(
        hotel: hotel,
        message: message,
        prospect_public_id: prospect.public_id,
        channel: CHANNEL
      ).call

      result.success? ? nil : result.error
    end

    def record_only(prospect, conversation)
      prospect.prospect_messages.create!(
        conversation: conversation,
        direction: "inbound",
        sender_role: "guest",
        body: message
      )
      prospect.touch_last_contact!
      nil
    end
  end
end
