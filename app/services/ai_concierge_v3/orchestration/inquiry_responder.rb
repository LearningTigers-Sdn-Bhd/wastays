module AiConciergeV3
  module Orchestration
    class InquiryResponder
    def initialize(hotel:, message:, phone: nil, prospect_public_id: nil)
      @hotel = hotel
      @message = message.to_s.strip
      @phone = phone.to_s.strip.presence
      @prospect_public_id = prospect_public_id.to_s.strip.presence
    end

    def call
      return error_result("AI Concierge is not enabled for this hotel.") unless hotel.ai_concierge_enabled?
      return error_result("AI Concierge is not fully configured for this hotel.") unless hotel.ai_concierge_ready?
      return error_result("Phone or prospect_public_id is required for AI concierge conversations") if phone.blank? && prospect_public_id.blank?

      TurnOrchestrator.new(
        hotel: hotel,
        message: message,
        phone: phone,
        prospect_public_id: prospect_public_id
      ).call
    rescue ProspectNotFoundError => e
      Result.failure(error: e.message, status: :not_found)
    rescue StandardError => e
      Rails.logger.error("AiConciergeV3::InquiryResponder error: #{e.class}: #{e.message}")
      Result.failure(error: "AI Concierge is temporarily unavailable.", status: :internal_server_error)
    end

    private

    attr_reader :hotel, :message, :phone, :prospect_public_id

    def error_result(message)
      Result.failure(error: message, status: :unprocessable_content)
    end
    end

    class ProspectNotFoundError < StandardError; end
  end
end
