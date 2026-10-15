# frozen_string_literal: true

module Admin
  module Hotels
    class UpdateService
      Result = Struct.new(:success?, :hotel, :error)

      def initialize(hotel:, hotel_params:)
        @hotel = hotel
        @hotel_params = hotel_params
      end

      def call
        ActiveRecord::Base.transaction do
          sanitize_amenities
          @hotel.update!(@hotel_params)

          # Boat features can be switched on long after creation. The service is
          # idempotent and no-ops while the toggle is off, so calling it on every
          # update is enough -- the hotel gets its timetable the first time the
          # toggle goes on, and nothing happens on any other save.
          Boats::EnsureDefaults.call(@hotel)
        end
        Result.new(true, @hotel, nil)
      rescue ActiveRecord::RecordInvalid => e
        error_message = e.record.errors.full_messages.to_sentence
        Result.new(false, @hotel, error_message)
      rescue => e
        Result.new(false, @hotel, e.message)
      end

      private

      def sanitize_amenities
        if @hotel_params[:amenities]
          @hotel_params[:amenities] = Array(@hotel_params[:amenities]).reject(&:blank?)
        end
      end
    end
  end
end
