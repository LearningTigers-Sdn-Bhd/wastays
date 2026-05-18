# frozen_string_literal: true

module HotelPortal
  class FolioTransactionsController < BaseController
    before_action :authorize_post_folio_transactions!
    before_action :set_booking

    def create
      unless @booking.booking_folio
        return redirect_to hotel_booking_path(current_hotel, @booking), alert: "Booking has no folio."
      end

      result = Folios::PostStaffTransaction.call(
        folio: @booking.booking_folio,
        user: current_user,
        transaction_type: folio_transaction_params[:transaction_type],
        category: folio_transaction_params[:category],
        amount: folio_transaction_params[:amount],
        description: folio_transaction_params[:description],
        posting_date: folio_transaction_params[:posting_date]
      )

      if result.success?
        redirect_to hotel_booking_path(current_hotel, @booking), notice: "Folio transaction posted."
      else
        redirect_to hotel_booking_path(current_hotel, @booking), alert: result.error
      end
    end

    private

    def authorize_post_folio_transactions!
      raise Pundit::NotAuthorizedError unless current_user.has_permission?("post_folio_transactions", hotel: current_hotel)
    end

    def set_booking
      @booking = current_hotel.bookings.find(params[:booking_id])
    end

    def folio_transaction_params
      params.require(:folio_transaction).permit(:transaction_type, :category, :amount, :description, :posting_date)
    end
  end
end
