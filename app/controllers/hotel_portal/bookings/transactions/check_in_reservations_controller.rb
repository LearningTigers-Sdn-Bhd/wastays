# frozen_string_literal: true

module HotelPortal
  module Bookings
    module Transactions
      class CheckInReservationsController < BaseController
        before_action :set_booking

        def show
          render "hotel_portal/bookings/transactions/check_in_reservation/offcanvas"
        end
      end
    end
  end
end
