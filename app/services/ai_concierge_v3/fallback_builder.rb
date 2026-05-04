module AiConciergeV3
  class FallbackBuilder
    DEFAULT_MESSAGE = "I'm unable to answer that right now. Please contact the hotel team for assistance.".freeze

    def initialize(message: DEFAULT_MESSAGE, action_name: nil, needs_human_support: true)
      @message = message
      @action_name = action_name
      @needs_human_support = needs_human_support
    end

    def call
      ResponsePayloadBuilder.new(
        reply_message: message,
        needs_human_support: needs_human_support,
        action_name: action_name
      ).call
    end

    private

    attr_reader :message, :action_name, :needs_human_support
  end
end
