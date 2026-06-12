# frozen_string_literal: true

module HotelPortal
  module Bookings
    module Transactions
      class CheckOutsController < BaseController
        before_action :set_booking

        def show
          render "hotel_portal/bookings/transactions/check_out/offcanvas"
        end
      end
    end
  end
end
