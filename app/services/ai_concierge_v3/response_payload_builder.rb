module AiConciergeV3
  class ResponsePayloadBuilder
    def initialize(reply_message:, needs_human_support:, action_name:)
      @reply_message = reply_message
      @needs_human_support = needs_human_support
      @action_name = action_name
    end

    def call
      {
        reply_message: reply_message,
        needs_human_support: needs_human_support,
        action_name: action_name
      }
    end

    private

    attr_reader :reply_message, :needs_human_support, :action_name
  end
end
