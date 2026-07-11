# frozen_string_literal: true

module HotelPortal
  module Bookings
    module Transactions
      class WalkInCheckInsController < BaseController
        def show
          return create if request.post?

          build_booking(source: "walk_in")
          render_new_booking(transaction: :walk_in_check_in)
        end

        private

        def create
          result = create_staff_booking(booking_type: "walk_in")
          return complete_new_booking(result.booking, notice: result.group_booking ? "Walk-in group checked in successfully." : "Walk-in guest checked in successfully.") if result.success?

          @booking = current_hotel.bookings.build(model_booking_params.merge(source: "walk_in"))
          result.errors.each { |error| @booking.errors.add(:base, error) }
          render_new_booking(transaction: :walk_in_check_in, status: :unprocessable_content)
        end
      end
    end
  end
end
