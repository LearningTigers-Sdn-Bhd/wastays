# frozen_string_literal: true

module Admin
  module Hotels
    class UpdateService
      Result = Struct.new(:success?, :hotel, :error)

      def initialize(hotel:, hotel_params:, salesperson_params:, current_user:)
        @hotel = hotel
        @hotel_params = hotel_params
        @salesperson_params = salesperson_params
        @current_user = current_user
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

          Admin::SyncHotelSalesperson.new(
            hotel: @hotel,
            name: @salesperson_params[:name],
            email: @salesperson_params[:email],
            current_user: @current_user
          ).call
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
