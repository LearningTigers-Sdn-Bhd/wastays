# frozen_string_literal: true

require "ostruct"

module HotelPortal
  module RoomTypes
    class SaveRoomType
      def initialize(hotel:, room_type: nil, params:)
        @hotel = hotel
        @room_type = room_type || @hotel.room_types.build
        @params = params.to_h
      end

      def call
        sanitize_room_numbers
        sanitize_amenities

        photos = @params.delete(:photos)
        @room_type.assign_attributes(@params)

        is_new_record = @room_type.new_record?

        if @room_type.save
          @room_type.attach_photos_with_limit(photos) if photos.present?
          @hotel.complete_rooms! if is_new_record
          sync_with_channel_manager
          OpenStruct.new(success?: true, room_type: @room_type)
        else
          OpenStruct.new(success?: false, room_type: @room_type)
        end
      end

      private

      def sanitize_room_numbers
        if @params[:room_numbers]
          @params[:room_numbers] = Array(@params[:room_numbers]).reject(&:blank?)
        else
          @params[:room_numbers] = []
        end
      end

      def sanitize_amenities
        if @params[:amenities]
          @params[:amenities] = Array(@params[:amenities]).reject(&:blank?)
        end
      end

      def sync_with_channel_manager
        return unless ChannelManagers::ConnectionState.provisioned?(@hotel)

        ChannelManagers::SyncStructureJob.perform_later(@room_type.class.name, @room_type.id, "sync")
      end
    end
  end
end
