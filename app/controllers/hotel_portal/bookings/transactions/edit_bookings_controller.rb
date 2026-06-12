# frozen_string_literal: true

module HotelPortal
  module Bookings
    module Transactions
      class EditBookingsController < BaseController
        before_action :set_booking

        def show
          return update if request.patch?

          render "hotel_portal/bookings/transactions/edit_booking/offcanvas"
        end

        private

        def update
          result = ::Bookings::UpdateStayService.new(
            booking: @booking,
            params: editable_booking_params,
            user: current_user
          ).call
          return complete_existing_booking(@booking, notice: "Booking details updated.") if result.success?

          result.errors.each { |error| @booking.errors.add(:base, error) }
          render "hotel_portal/bookings/transactions/edit_booking/offcanvas", status: :unprocessable_content
        end

        def editable_booking_params
          booking_params.slice(
            :guest_name, :guest_email, :guest_phone, :guest_country, :guest_gender,
            :guest_document_type, :guest_government_id, :source, :guarantee_method
          )
        end
      end
    end
  end
end
