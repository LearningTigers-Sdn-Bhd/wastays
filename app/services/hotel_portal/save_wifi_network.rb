# frozen_string_literal: true

module HotelPortal
  class SaveWifiNetwork
    def initialize(hotel:, network:, attributes:)
      @hotel = hotel
      @network = network
      @attributes = attributes.to_h.symbolize_keys
    end

    def call
      preserve_saved_password

      HotelWifiNetwork.transaction do
        if ActiveModel::Type::Boolean.new.cast(attributes[:primary_network])
          hotel.hotel_wifi_networks.where.not(id: network.id).update_all(primary_network: false)
        end
        network.assign_attributes(attributes)
        network.save!
        select_primary_network
      end

      true
    rescue ActiveRecord::RecordInvalid
      false
    end

    private

    attr_reader :hotel, :network, :attributes

    def preserve_saved_password
      attributes.delete(:password) if network.persisted? && attributes[:password].blank?
    end

    def select_primary_network
      return if hotel.hotel_wifi_networks.exists?(primary_network: true)

      hotel.hotel_wifi_networks.active.in_display_order.first&.update!(primary_network: true)
    end
  end
end
