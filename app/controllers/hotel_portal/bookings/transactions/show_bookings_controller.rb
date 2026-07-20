# frozen_string_literal: true

module HotelPortal
  module Bookings
    module Transactions
      class ShowBookingsController < BaseController
        before_action :set_booking
        before_action :set_panel_presenter
        before_action :set_stay_view_capabilities

        def show
          render "hotel_portal/bookings/transactions/show_booking/offcanvas"
        end

        def print_send
          return redirect_to hotel_booking_transaction_show_booking_path(current_hotel, @booking), alert: "Print / Send group view is only available for group bookings." unless @booking.group_booking_id?

          render "hotel_portal/bookings/transactions/show_booking/print_send_group"
        end

        private

        def set_panel_presenter
          @panel_presenter = HotelPortal::BookingControlPanelPresenter.new(
            @booking,
            params: @booking.group_booking_id? ? { scope: "group" } : {},
            hotel: current_hotel,
            booking_presenter: @presenter
          )
        end

        def set_stay_view_capabilities
          return unless @transaction_source == "stay_view"

          @stay_view_capabilities = ::StayView::BuildCapabilities.call(user: current_user, hotel: current_hotel)
        end
      end
    end
  end
end
