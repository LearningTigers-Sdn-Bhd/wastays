module AiConcierge
  module Orchestration
    module Core
      class InquiryResponder
    MAX_MESSAGE_LENGTH = 2_000

    def initialize(hotel:, message:, phone: nil, prospect_public_id: nil, channel: nil,
                   record_inbound: true)
      @hotel = hotel
      @message = message.to_s.strip
      @phone = phone.to_s.strip.presence
      @prospect_public_id = prospect_public_id.to_s.strip.presence
      @channel = channel.presence
      @record_inbound = record_inbound
    end

    def call
      return error_result("AI Concierge is not enabled for this hotel.") unless hotel.ai_concierge_enabled?
      return error_result("AI Concierge is not fully configured for this hotel.") unless hotel.ai_concierge_ready?
      return error_result("Phone or prospect_public_id is required for AI concierge conversations") if phone.blank? && prospect_public_id.blank?
      return error_result("Message is too long (max #{MAX_MESSAGE_LENGTH} characters)") if message.length > MAX_MESSAGE_LENGTH

      AiConcierge::Orchestration::TurnOrchestrator.new(
        hotel: hotel,
        message: message,
        phone: phone,
        prospect_public_id: prospect_public_id,
        channel: channel,
        record_inbound: record_inbound
      ).call
    rescue StandardError => e
      Rails.logger.error("AiConcierge::Orchestration::Core::InquiryResponder error: #{e.class}: #{e.message}")
      Result.failure(error: "AI Concierge is temporarily unavailable.", status: :internal_server_error)
    end

    private

    attr_reader :hotel, :message, :phone, :prospect_public_id, :channel, :record_inbound

    def error_result(message)
      Result.failure(error: message, status: :unprocessable_content)
    end
      end
    end
  end
end
