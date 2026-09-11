# frozen_string_literal: true

require "ostruct"

module HotelPortal
  module RoomTypes
    class DestroyPhotos
      def initialize(room_type:, photo_ids:)
        @room_type = room_type
        @photo_ids = Array(photo_ids).reject(&:blank?)
      end

      def call
        if @photo_ids.blank?
          return OpenStruct.new(success?: false, message: "No photos selected.")
        end

        ActiveRecord::Base.transaction do
          attachments = @room_type.photos.attachments.where(id: @photo_ids)

          if attachments.any?
            # Hand the featured slot on before the photos go, so a category with
            # photos left never ends up without a cover for the room row.
            @room_type.promote_featured_photo_before_removing(attachments.pluck(:id))
            attachments.each(&:purge)
            OpenStruct.new(success?: true, message: "Selected photos deleted successfully.")
          else
            OpenStruct.new(success?: false, message: "Photos not found.")
          end
        end
      rescue => e
        OpenStruct.new(success?: false, message: "Failed to delete photos: #{e.message}")
      end
    end
  end
end
