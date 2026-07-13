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
          result = create_staff_booking
          return complete_new_booking(result.booking, notice: result.group_booking ? "Group booking created successfully." : "Booking created successfully.") if result.success?

          render_new_booking_failure(transaction: :new_booking, errors: result.errors)
        end
      end
    end
  end
end
