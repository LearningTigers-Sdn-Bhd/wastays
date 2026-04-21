require "ostruct"

module ChannelManagers
  class OnboardingService
    def initialize(hotel:)
      @hotel = hotel
    end

    def call
      return failure("Channel manager not selected for this hotel") if @hotel.preferred_channel_manager.blank?

      adapter = ChannelManagers::SyncOrchestrator.adapter_for(@hotel)
      adapter.onboard_hotel
    rescue StandardError => e
      failure("Onboarding failed: #{e.message}")
    end

    private

    def failure(message)
      OpenStruct.new(success?: false, message: message)
    end
  end
end
