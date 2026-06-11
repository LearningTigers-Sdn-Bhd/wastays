# frozen_string_literal: true

module HotelPortal
  module Bookings
    module Transactions
      class CancelBookingsController < BaseController
        before_action :set_booking

        def show
          render "hotel_portal/bookings/transactions/cancel_booking/offcanvas"
        end
      end
    end
  end
end
