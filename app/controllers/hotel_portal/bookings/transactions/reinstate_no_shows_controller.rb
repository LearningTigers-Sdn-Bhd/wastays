# frozen_string_literal: true

module HotelPortal
  module Bookings
    module Transactions
      class ReinstateNoShowsController < BaseController
        before_action :set_booking

        def show
          if @booking.group_booking_id?
            @group_reinstatement_bookings = @booking.group_booking.bookings
              .includes(booking_rooms: [ :room_type, :rate_plan ], booking_guests: :guest)
              .order(:group_position, :id)
          end
          render "hotel_portal/bookings/transactions/reinstate_no_show/offcanvas"
        end
      end
    end
  end
end
