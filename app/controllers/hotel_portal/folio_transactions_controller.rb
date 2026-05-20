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

      authorize_folio_permission!(permission_for_folio_posting) if staff_posting_category?

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

      authorize_folio_permission!("post_folio_corrections")

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

    def authorize_folio_permission!(permission)
      raise Pundit::NotAuthorizedError unless current_user.has_permission?(permission, hotel: current_hotel)
    end

    def permission_for_folio_posting
      FOLIO_POSTING_PERMISSIONS[folio_posting_key]
    end

    def staff_posting_category?
      transaction_type, category = folio_posting_key
      category.in?(Folios::PostStaffTransaction::ALLOWED_CATEGORIES.fetch(transaction_type, []))
    end

    def folio_posting_key
      [
        folio_transaction_params[:transaction_type].to_s,
        folio_transaction_params[:category].to_s
      ]
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
