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
        @room_type.assign_attributes(@params)

        if @room_type.save
          @hotel.complete_rooms! if @room_type.previously_new_record?
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
    end
  end
end
