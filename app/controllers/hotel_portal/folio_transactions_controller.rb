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
        redirect_after_post(notice: "Folio transaction posted.")
      else
        redirect_after_post(alert: result.error)
      end
    end

    def reverse
      unless @booking.booking_folio
        return redirect_to hotel_booking_path(current_hotel, @booking), alert: "Booking has no folio."
      end

      transaction = @booking.booking_folio.folio_transactions.find(params[:id])
      result = Folios::ReverseTransaction.call(
        transaction: transaction,
        user: current_user,
        correction_reason: reversal_params[:correction_reason],
        correction_note: reversal_params[:correction_note],
        posting_date: reversal_params[:posting_date].presence || Time.current.to_date,
        options: reversal_options
      )

      if result.success?
        redirect_after_post(notice: "Folio transaction reversed.")
      else
        redirect_after_post(alert: result.error)
      end
    end

    private

    def redirect_after_post(options = {})
      if params[:redirect_to_folio] == "true"
        redirect_to folio_hotel_booking_path(current_hotel, @booking), options
      else
        redirect_to hotel_booking_path(current_hotel, @booking), options
      end
    end

    def authorize_post_folio_transactions!
      raise Pundit::NotAuthorizedError unless current_user.has_permission?("post_folio_transactions", hotel: current_hotel)
    end

    def set_booking
      @booking = current_hotel.bookings.find(params[:booking_id])
    end

    def folio_transaction_params
      params.require(:folio_transaction).permit(:transaction_type, :category, :amount, :description, :posting_date)
    end

    def reversal_params
      params.require(:folio_transaction).permit(
        :correction_reason,
        :correction_note,
        :posting_date,
        :override_closed_folio,
        :override_night_audit
      )
    end

    def reversal_options
      {
        override_closed_folio: ActiveModel::Type::Boolean.new.cast(reversal_params[:override_closed_folio]),
        override_night_audit: ActiveModel::Type::Boolean.new.cast(reversal_params[:override_night_audit])
      }
    end
  end
end
