# frozen_string_literal: true

module HotelPortal
  class FolioTransactionsController < BaseController
    before_action :set_booking

    FOLIO_POSTING_PERMISSIONS = {
      [ "charge", "other" ] => "post_folio_charges",
      [ "payment", "" ] => "post_folio_payments",
      [ "payment", "cash" ] => "post_folio_payments",
      [ "payment", "booking_payment" ] => "post_folio_payments",
      [ "payment", "gateway_payment" ] => "post_folio_payments",
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
      return redirect_after_post(alert: "You do not have permission to post this folio transaction.") unless allowed_to_post_folio_transaction?

      result = ::Folios::PostStaffTransaction.call(
        folio: @booking.booking_folio,
        user: current_user,
        transaction_type: folio_transaction_params[:transaction_type],
        category: folio_transaction_params[:category],
        amount: folio_transaction_params[:amount],
        description: folio_transaction_params[:description],
        posting_date: folio_transaction_params[:posting_date],
        transaction_code_id: folio_transaction_params[:transaction_code_id],
        options: posting_options
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
      policy = ::Folios::TransactionActionPolicy.new(
        transaction: transaction,
        user: current_user,
        posting_date: current_hotel.current_business_date
      )
      return redirect_after_post(alert: policy.reverse_error) unless policy.reverse_allowed?

      result = ::Folios::ReverseTransaction.call(
        transaction: transaction,
        user: current_user,
        correction_reason: reversal_params[:correction_reason],
        correction_note: reversal_params[:correction_note],
        posting_date: current_hotel.current_business_date
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
      params.require(:folio_transaction).permit(
        :transaction_type,
        :category,
        :transaction_code_id,
        :amount,
        :description,
        :posting_date,
        :reference,
        :note,
        :payment_source,
        :refund_source
      )
    end

    def posting_options
      options = {}
      options[:require_transaction_code] = true if folio_transaction_params[:transaction_type].to_s == "charge"
      if folio_transaction_params[:transaction_type].to_s == "payment" && !refund_transaction?
        options[:payment_source] = folio_transaction_params[:payment_source].to_s.strip
      end

      metadata = {}
      metadata[:reference] = folio_transaction_params[:reference].to_s.strip if folio_transaction_params[:reference].present?
      metadata[:note] = folio_transaction_params[:note].to_s.strip if folio_transaction_params[:note].present?
      if refund_transaction? && folio_transaction_params[:refund_source].present?
        metadata[:refund_source] = folio_transaction_params[:refund_source].to_s.strip
      end
      options[:metadata] = metadata if metadata.any?

      options
    end

    def refund_transaction?
      folio_transaction_params[:transaction_type].to_s == "payment" &&
        folio_transaction_params[:category].to_s == "refund"
    end

    def allowed_to_post_folio_transaction?
      slug = posting_permission_slug
      slug.present? && current_user.has_permission?(slug, hotel: current_hotel)
    end

    def posting_permission_slug
      type = folio_transaction_params[:transaction_type].to_s
      category = folio_transaction_params[:category].to_s
      return "execute_folio_refunds" if type == "payment" && category == "refund"
      return "post_folio_payments" if type == "payment" && folio_transaction_params[:payment_source].present?
      return "post_folio_payments" if type == "payment" && category != "refund"
      return "post_folio_charges" if type == "charge"

      FOLIO_POSTING_PERMISSIONS.fetch([ type, category ], nil)
    end

    def reversal_params
      params.require(:folio_transaction).permit(
        :correction_reason,
        :correction_note
      )
    end
  end
end
