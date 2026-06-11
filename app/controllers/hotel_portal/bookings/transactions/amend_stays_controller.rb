# frozen_string_literal: true

module HotelPortal
  module Bookings
    module Transactions
      class AmendStaysController < BaseController
        before_action :set_booking

        def show
          @room_types = current_hotel.room_types.order(:name)
          return update if request.patch?

          render "hotel_portal/bookings/transactions/amend_stay/offcanvas"
        end

        private

        def update
          result = ::Bookings::UpdateStayService.new(booking: @booking, params: amend_stay_params, user: current_user).call
          return complete_existing_booking(@booking, notice: "Stay amended successfully.") if result.success?

          @booking.errors.add(:base, result.errors.to_sentence)
          render "hotel_portal/bookings/transactions/amend_stay/offcanvas", status: :unprocessable_content
        end

        def amend_stay_params
          booking_params.slice(
            :check_in, :check_out, :adults, :children, :room_type_id, :room_number,
            :rate_plan_id, :total_amount, :manual_rate_override
          )
        end
      end
    end
  end
end
