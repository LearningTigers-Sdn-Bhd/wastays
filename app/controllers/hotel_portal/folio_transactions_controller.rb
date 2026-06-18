# frozen_string_literal: true

module HotelPortal
  class FolioTransactionsController < BaseController
    before_action :set_booking

    FOLIO_POSTING_PERMISSIONS = {
      [ "charge", "other" ] => "post_folio_charges",
      [ "payment", "cash" ] => "post_folio_payments",
      [ "payment", "refund" ] => "execute_folio_refunds",
      [ "adjustment", "adjustment" ] => "post_folio_adjustments",
      [ "adjustment", "discount" ] => "post_folio_adjustments",
      [ "adjustment", "other" ] => "post_folio_adjustments",
      [ "adjustment", "correction" ] => "post_folio_corrections",
      [ "adjustment", "write_off" ] => "post_folio_write_offs"
    }.freeze

    def create
      unless @booking.booking_folio
        return redirect_to hotel_booking_path(current_hotel, @booking), alert: "Booking has no folio."
      end

      result = ::Folios::PostStaffTransaction.call(
        folio: @booking.booking_folio,
        user: current_user,
        transaction_type: folio_transaction_params[:transaction_type],
        category: folio_transaction_params[:category],
        amount: folio_transaction_params[:amount],
        description: folio_transaction_params[:description],
        posting_date: folio_transaction_params[:posting_date],
        transaction_code_id: folio_transaction_params[:transaction_code_id]
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
      result = ::Folios::ReverseTransaction.call(
        transaction: transaction,
        user: current_user,
        correction_reason: reversal_params[:correction_reason],
        correction_note: reversal_params[:correction_note],
        posting_date: reversal_params[:posting_date].presence || current_hotel.current_business_date
      )

      if result.success?
        redirect_after_post(notice: "Folio transaction reversed.")
      else
        redirect_after_post(alert: result.error)
      end
    end

    private

    def redirect_after_post(options = {})
      if params[:redirect_to_checkout] == "true"
        redirect_to hotel_booking_transaction_check_out_path(current_hotel, @booking), options
      elsif params[:redirect_to_folio] == "true"
        redirect_to hotel_folio_path(current_hotel, @booking, folio_origin_params), options
      else
        redirect_to hotel_booking_path(current_hotel, @booking), options
      end
    end

    def folio_origin_params
      params[:folio_origin] == "folios" ? { origin: "folios" } : {}
    end

    def set_booking
      @booking = current_hotel.bookings.find(params[:booking_id])
    end

    def folio_transaction_params
      params.require(:folio_transaction).permit(:transaction_type, :category, :transaction_code_id, :amount, :description, :posting_date)
    end

    def reversal_params
      params.require(:folio_transaction).permit(
        :correction_reason,
        :correction_note,
        :posting_date
      )
    end
  end
end
