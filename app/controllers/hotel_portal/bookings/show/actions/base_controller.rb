# frozen_string_literal: true

module HotelPortal
  module Bookings
    module Show
      module Actions
        class BaseController < HotelPortal::BaseController
          include OffcanvasTransactionCompletion

          before_action :authorize_manage_bookings!
          before_action :set_booking
          before_action :set_return_to

          private

          def set_booking
            @booking = current_hotel.bookings
                                    .includes(booking_guests: :guest, booking_notes: :user)
                                    .find(params[:booking_id])
            @presenter = HotelPortal::BookingPresenter.new(@booking, current_hotel)
          end

          def set_return_to
            @return_to = offcanvas_return_to(fallback: hotel_booking_path(current_hotel, @booking))
          end

          def complete_action(notice:)
            offcanvas_transaction_response(destination: @return_to, notice: notice)
          end

          def authorize_manage_bookings!
            raise Pundit::NotAuthorizedError unless current_user.has_permission?("manage_bookings", hotel: current_hotel)
          end
        end
      end
    end
  end
end
