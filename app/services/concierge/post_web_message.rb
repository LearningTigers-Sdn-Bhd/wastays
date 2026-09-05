# frozen_string_literal: true

module Concierge
  # A message typed into the chat on the public concierge page.
  #
  # The bot answering is an enhancement, not the mechanism. A hotel with no AI
  # provider configured still gets a working message desk: the guest writes, the
  # thread appears in the portal inbox, and a person answers. The same is true
  # once staff take a thread over -- the bot goes quiet and the message is
  # simply filed.
  #
  # Filing what the guest typed is the whole of the request. The answer, when
  # there is a bot to give one, is a job -- so the guest sees their own message
  # the moment they send it rather than watching a spinner for however long a
  # model takes, and a model that is slow or down costs them a wait rather than
  # their message.
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

      record(prospect, conversation)
      AnswerWebMessageJob.perform_later(conversation.id, message) if bot_answers?(conversation)

      Result.new(prospect: prospect, conversation: conversation.reload)
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
      OpenConversation.new(prospect: prospect, channel: CHANNEL).call
    end

    def bot_answers?(conversation)
      hotel.ai_concierge_ready? && conversation.bot?
    end

    # Always, and before anything else can fail. The assistant is told not to
    # file it again (`record_inbound: false` on the way down), so this is the
    # one place a guest's message is written whether a bot answers it or not.
    def record(prospect, conversation)
      prospect.prospect_messages.create!(
        conversation: conversation,
        direction: "inbound",
        sender_role: "guest",
        body: message
      )
      clear_suggestions(prospect)
      prospect.touch_last_contact!
    end

    def clear_suggestions(prospect)
      state = prospect.prospect_conversation_state
      return unless state

      manager = AiConcierge::State::ConversationTaskManager.new(slots_payload: state.slots_payload)
      state.update!(slots_payload: manager.clear_suggestions)
    end
  end
end
