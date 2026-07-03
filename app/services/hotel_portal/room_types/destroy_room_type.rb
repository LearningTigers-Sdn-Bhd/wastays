# frozen_string_literal: true

require "ostruct"

module HotelPortal
  module RoomTypes
    class DestroyRoomType
      def initialize(room_type:)
        @room_type = room_type
        @hotel = room_type.hotel
      end

      def call
        external_id = @room_type.channel_mapping&.external_id
        synced = synced_with_channel_manager?

        if @room_type.destroy
          if synced && external_id.present?
            ChannelManagers::SyncStructureJob.perform_later(
              "RoomType",
              nil,
              "delete",
              hotel_id: @hotel.id,
              external_id: external_id
            )
          end
          OpenStruct.new(success?: true)
        else
          OpenStruct.new(success?: false, errors: @room_type.errors)
        end
      end

      private

      def synced_with_channel_manager?
        @hotel.preferred_channel_manager.present? &&
          @room_type.channel_mapping.present? &&
          @room_type.channel_mapping.external_id != "pending"
      end
    end
  end
end
