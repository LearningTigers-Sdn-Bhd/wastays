# frozen_string_literal: true

module HotelPortal
  module Bookings
    module Actions
      # Shared read-only setup for the booking summary and document views.
      class OverviewBaseController < BaseController
        skip_before_action :authorize_manage_bookings!
        prepend_before_action :authorize_view_bookings!
        before_action :set_panel_presenter

        private

        def set_booking
          @booking = current_hotel.bookings
                                  .includes(
                                    booking_folios: [ :folio_transactions, :folio_forecasted_charges ],
                                    booking_rooms: [ :room_type, :rate_plan ],
                                    booking_guests: :guest,
                                    group_booking: {
                                      bookings: [
                                        { booking_folios: [ :folio_transactions, :folio_forecasted_charges ] },
                                        { booking_rooms: [ :room_type, :rate_plan ] },
                                        { booking_guests: :guest }
                                      ]
                                    }
                                  )
                                  .find(params[:booking_id])
          @presenter = HotelPortal::BookingPresenter.new(@booking, current_hotel)
        end

        def set_panel_presenter
          @panel_presenter = HotelPortal::BookingControlPanelPresenter.new(
            @booking,
            params: (@booking.group_booking_id? ? { scope: "group" } : {}),
            hotel: current_hotel,
            booking_presenter: @presenter
          )
        end

        def authorize_view_bookings!
          raise Pundit::NotAuthorizedError unless current_user.has_permission?("view_bookings", hotel: current_hotel)
        end

        def navigation_params
          { source: params[:source].presence, return_to: params[:return_to].presence }.compact
        end
      end
    end
  end
end
