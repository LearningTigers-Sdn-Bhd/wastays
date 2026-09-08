# frozen_string_literal: true

module HotelPortal
  class DestroyWifiNetwork
    def initialize(hotel:, network:)
      @hotel = hotel
      @network = network
    end

    def call
      was_primary = network.primary_network?

      HotelWifiNetwork.transaction do
        network.destroy!
        promote_first_network if was_primary
      end
    end

    private

    attr_reader :hotel, :network

    def promote_first_network
      replacement = hotel.hotel_wifi_networks.active.in_display_order.first ||
        hotel.hotel_wifi_networks.in_display_order.first
      replacement&.update!(primary_network: true)
    end
  end
end
