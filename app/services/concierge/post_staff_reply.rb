# frozen_string_literal: true

module Concierge
  # A reply typed by a person in the inbox.
  #
  # Writing a reply is itself the act of taking the thread over: a staff member
  # who has answered is holding the conversation, and the bot answering over
  # the top of them would give the guest two answers to one question.
  #
  # A reply that cannot travel is refused rather than filed, in the same words
  # the reply box uses. A stored reply the guest never sees is worse than no
  # reply box at all -- staff believe they have answered.
  class PostStaffReply
    MAX_MESSAGE_LENGTH = 2_000

    Result = Struct.new(:message, :conversation, :error, keyword_init: true) do
      def success? = error.blank?
    end

    def initialize(conversation:, user:, body:)
      @conversation = conversation
      @user = user
      @body = body.to_s.strip
    end

    def call
      error = refusal
      return Result.new(conversation: conversation, error: error) if error

      message = nil

      ActiveRecord::Base.transaction do
        TakeOverConversation.new(conversation: conversation, user: user).call
        message = create_reply
      end

      Result.new(message: message, conversation: conversation.reload)
    end

    private

    attr_reader :conversation, :user, :body

    def refusal
      return "Type a message before sending." if body.blank?
      return "That message is too long." if body.length > MAX_MESSAGE_LENGTH
      return "This conversation is closed. Reopen it to reply." unless conversation.open?
      return conversation.reply_blocker_message unless conversation.replies_reach_guest?

      nil
    end

    def create_reply
      conversation.messages.create!(
        prospect: conversation.prospect,
        direction: "outbound",
        sender_role: "staff",
        sender_user: user,
        body: body
      )
    end
  end
end
