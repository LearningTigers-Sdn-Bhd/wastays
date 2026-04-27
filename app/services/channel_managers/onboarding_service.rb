# frozen_string_literal: true

require "ostruct"

module ChannelManagers
  class OnboardingService
    def initialize(hotel:)
      @hotel = hotel
    end

    def call
      return failure("Channel manager not selected for this hotel") if @hotel.preferred_channel_manager.blank?

      adapter = ChannelManagers::SyncOrchestrator.adapter_for(@hotel)
      result = adapter.onboard_hotel

      # Log full result for debugging
      unless result.success?
        Rails.logger.error "Onboarding Failed for Hotel #{@hotel.id}: #{result.message}"
      end

      result
    rescue StandardError => e
      Rails.logger.error "Onboarding Exception for Hotel #{@hotel.id}: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
      failure("Onboarding failed: #{e.message}")
    end

    private

    def failure(message)
      OpenStruct.new(success?: false, message: message)
    end
  end
end
