# frozen_string_literal: true

module Rooms
  class SaveSeedRoomType
    def self.call!(...) = new(...).call!

    def initialize(hotel:, attributes:)
      @hotel = hotel
      @attributes = attributes.to_h.symbolize_keys
    end

    def call!
      room_type = hotel.room_types.find_or_initialize_by(name: attributes.fetch(:name))

      RoomType.transaction do
        room_type.lock! if room_type.persisted?
        room_type.assign_attributes(attributes)
        room_type.save!
        SyncFromRoomType.call!(room_type:)
      end

      room_type
    end

    private

    attr_reader :hotel, :attributes
  end
end
