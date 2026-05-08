module AiConciergeV3
  module Orchestration
    class ResponsePayloadBuilder
    def initialize(reply_message:, needs_human_support:, action_name:, prospect_public_id: nil)
      @reply_message = reply_message
      @needs_human_support = needs_human_support
      @action_name = action_name
      @prospect_public_id = prospect_public_id
    end

    def call
      {
        reply_message: reply_message,
        needs_human_support: needs_human_support,
        action_name: action_name
      }.tap do |payload|
        payload[:prospect_public_id] = prospect_public_id if prospect_public_id.present?
      end
    end

    private

    attr_reader :reply_message, :needs_human_support, :action_name, :prospect_public_id
    end
  end
end
