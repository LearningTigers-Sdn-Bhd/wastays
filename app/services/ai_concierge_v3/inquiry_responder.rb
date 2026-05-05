module AiConciergeV3
  class InquiryResponder
    def initialize(hotel:, message:, phone: nil)
      @hotel = hotel
      @message = message.to_s.strip
      @phone = phone.to_s.strip.presence
    end

    def call
      return error_result("AI Concierge is not enabled for this hotel.") unless hotel.ai_concierge_enabled?
      return error_result("AI Concierge is not fully configured for this hotel.") unless hotel.ai_concierge_ready?

      TurnOrchestrator.new(
        hotel: hotel,
        message: message,
        phone: phone,
        identity_mode: identity_mode
      ).call
    rescue StandardError => e
      Rails.logger.error("AiConciergeV3::InquiryResponder error: #{e.class}: #{e.message}")
      Result.success(payload: MessageBuilders::FallbackBuilder.new.call)
    end

    private

    attr_reader :hotel, :message, :phone

    def identity_mode
      phone.present? ? :known_contact : :incognito
    end

    def error_result(message)
      Result.failure(error: message, status: :unprocessable_content)
    end
  end
end
