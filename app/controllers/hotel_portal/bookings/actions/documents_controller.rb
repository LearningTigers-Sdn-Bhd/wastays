# frozen_string_literal: true

module HotelPortal
  module Bookings
    module Actions
      # Group Print / Send documents. A standalone, lazily-loaded action: launch it
      # into `booking_action_sheet_secondary` to stack it above the booking summary,
      # or into `booking_action_sheet` to open it on its own.
      class DocumentsController < OverviewBaseController
        def show
          unless @booking.group_booking_id?
            return redirect_to hotel_booking_action_show_booking_path(current_hotel, @booking, navigation_params),
              alert: "Print / Send group view is only available for group bookings."
          end

          render :show, layout: false
        end
      end
    end
  end
end
