# frozen_string_literal: true

module HotelPortal
  module Bookings
    module Transactions
      class LateCheckoutsController < BaseController
        before_action :set_booking

        def show
          render "hotel_portal/bookings/transactions/late_checkout/offcanvas"
        end
      end
    end
  end
end
