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
        preload_destroy_cascade

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

      # Destroying a category cascades into every rate-plan assignment and each
      # assignment's own dependents. Load them in one pass so the cascade walks
      # in-memory records instead of querying per assignment.
      def preload_destroy_cascade
        ActiveRecord::Associations::Preloader.new(
          records: [ @room_type ],
          associations: { room_type_rate_plans: [ :occupancy_prices, :age_band_prices, :channel_mapping ] }
        ).call
      end

      def synced_with_channel_manager?
        @room_type.channel_mapping.present? &&
          @room_type.channel_mapping.external_id.present? &&
          @room_type.channel_mapping.external_id != "pending"
      end
    end
  end
end
