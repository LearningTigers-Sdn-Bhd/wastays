# frozen_string_literal: true

module HotelPortal
  module Bookings
    module Transactions
      class ReinstateNoShowsController < BaseController
        before_action :set_booking

        def show
          render "hotel_portal/bookings/transactions/reinstate_no_show/offcanvas"
        end
      end
    end
  end
end
