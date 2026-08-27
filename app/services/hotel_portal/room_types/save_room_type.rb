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
        saved = false

        RoomType.transaction do
          @room_type.lock! if @room_type.persisted?
          @room_type.assign_attributes(@params)

          unless @room_type.save
            raise ActiveRecord::Rollback
          end

          room_sync = Rooms::SyncFromRoomType.call(room_type: @room_type)
          unless room_sync.success?
            raise ActiveRecord::Rollback
          end

          saved = true
        end

        if saved
          @room_type.attach_photos_with_limit(photos) if photos.present?
          report_directory_drift
          sync_with_channel_manager
          OpenStruct.new(success?: true, room_type: @room_type)
        else
          OpenStruct.new(success?: false, room_type: @room_type)
        end
      end

      private

      # The rooms table is the source of truth and `room_types.room_numbers`
      # is its copy. The sync above writes both in one transaction, so a
      # difference here means a defect, not bad input. Report it and let the
      # save stand: a rollback would throw away correct work and hide the
      # defect.
      def report_directory_drift
        result = Rooms::ReconcileDirectory.call(hotel: @hotel)
        return if result.reconciled?

        Rails.logger.warn(
          "Room directory drift for hotel #{@hotel.id} after saving room type #{@room_type.id}: " \
          "#{result.issues.map(&:message).join(' | ')}"
        )
      rescue StandardError => error
        Rails.logger.warn("Room directory reconciliation failed for hotel #{@hotel.id}: #{error.message}")
      end

      def sanitize_room_numbers
        if @params[:room_numbers]
          @params[:room_numbers] = Array(@params[:room_numbers])
            .flatten
            .compact
            .map { |number| number.to_s.strip }
            .reject(&:blank?)
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
