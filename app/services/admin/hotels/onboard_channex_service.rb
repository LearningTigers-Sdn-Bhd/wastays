# frozen_string_literal: true

module Admin
  module Hotels
    class OnboardChannexService
      Result = Struct.new(:success?, :message)

      def initialize(hotel:)
        @hotel = hotel
      end

      def call
        @hotel.update!(preferred_channel_manager: "channex")
        ChannelManagers::OnboardingService.new(hotel: @hotel).call
      end
    end
  end
end
