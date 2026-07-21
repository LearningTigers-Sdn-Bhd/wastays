# frozen_string_literal: true

module HotelPortal
  module Bookings
    module Transactions
      class BaseController < HotelPortal::BaseController
        include OffcanvasTransactionCompletion
        include GroupLifecycleTargeting

        before_action :authorize_manage_bookings!
        before_action :set_transaction_source
        before_action :set_transaction_return_to

        private

        def set_transaction_source
          @transaction_source = params[:source].presence
        end

        def set_transaction_return_to
          @transaction_return_to = offcanvas_return_to(fallback: request.referer)
        end

        def complete_existing_booking(booking, notice:)
          offcanvas_transaction_response(
            destination: offcanvas_return_to(fallback: hotel_booking_control_panel_path(current_hotel, booking, tab: "booking_details")),
            notice: notice
          )
        end

        def set_booking
          @booking = current_hotel.bookings
                                  .includes(
                                    booking_folio: [ :folio_transactions, :folio_forecasted_charges ],
                                    booking_rooms: [ :room_type, :rate_plan ],
                                    booking_guests: :guest,
                                    booking_notes: :user
                                  )
                                  .find(params[:booking_id])
          @presenter = HotelPortal::BookingPresenter.new(@booking, current_hotel)
        end

        def booking_params
          params.fetch(:booking, {}).permit(:checked_in_at)
        end

        def authorize_manage_bookings!
          raise Pundit::NotAuthorizedError unless current_user.has_permission?("manage_bookings", hotel: current_hotel)
        end
      end
    end
  end
end
