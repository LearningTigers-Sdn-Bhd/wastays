# frozen_string_literal: true

module HotelPortal
  module Bookings
    module Transactions
      class NewBookingsController < BaseController
        def show
          return create if request.post?

          build_booking
          render_new_booking(transaction: :new_booking)
        end

        private

        def create
          result = create_manual_booking
          return complete_new_booking(result.booking, notice: "Booking created successfully.") if result.success?

          @booking = current_hotel.bookings.build(model_booking_params)
          result.errors.each { |error| @booking.errors.add(:base, error) }
          render_new_booking(transaction: :new_booking, status: :unprocessable_content)
        end
      end
    end
  end
end
