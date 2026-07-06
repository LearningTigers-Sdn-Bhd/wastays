# frozen_string_literal: true

module HotelPortal
  module Bookings
    module Transactions
      class QuickBookingsController < BaseController
        def show
          return create if request.post?

          build_booking
          render_new_booking(transaction: :quick_booking)
        end

        private

        def create
          params[:booking] ||= {}
          params[:booking][:record_payment] = "0"
          result = create_staff_booking(booking_type: "reservation")
          return complete_new_booking(result.booking, notice: result.group_booking ? "Group booking confirmed." : "Booking confirmed.") if result.success?

          render_new_booking_failure(transaction: :quick_booking, errors: result.errors)
        end
      end
    end
  end
end
