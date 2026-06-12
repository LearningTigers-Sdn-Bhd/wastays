# frozen_string_literal: true

module HotelPortal
  module Bookings
    module Transactions
      class MarkNoShowsController < BaseController
        before_action :set_booking

        def show
          return redirect_to hotel_booking_path(current_hotel, @booking), alert: "Booking is not pending no-show review." unless @booking.status == "review_no_show"

          render "hotel_portal/bookings/transactions/mark_no_show/offcanvas"
        end
      end
    end
  end
end
