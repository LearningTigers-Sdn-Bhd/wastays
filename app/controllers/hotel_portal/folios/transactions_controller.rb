# frozen_string_literal: true

module HotelPortal
  module Folios
    class TransactionsController < HotelPortal::FolioTransactionsController
      private

      def set_booking
        @booking = current_hotel.bookings.find(params[:folio_booking_id])
      end
    end
  end
end
