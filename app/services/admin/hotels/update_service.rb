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
          @hotel.update!(@hotel_params)

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
    end
  end
end
