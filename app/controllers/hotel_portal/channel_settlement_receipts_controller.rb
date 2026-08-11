# frozen_string_literal: true

module HotelPortal
  class ChannelSettlementReceiptsController < ReportsBaseController
    before_action :authorize_manage_ar_payments!
    before_action :set_breadcrumbs

    def new
      @form = HotelPortal::ChannelSettlementReceiptForm.new(
        booking_source_id: params[:booking_source_id],
        currency: params[:currency].presence || current_hotel.default_currency,
        settlement_method: "bank_transfer",
        received_at: Time.current
      )
      set_context
    end

    def create
      result = ChannelSettlements::RecordReceipt.call(
        hotel: current_hotel,
        user: current_user,
        attributes: receipt_params,
        allocations: params.fetch(:allocations, {})
      )

      if result.success?
        redirect_to channel_settlements_hotel_reports_path(current_hotel),
          notice: "OTA settlement receipt recorded."
      else
        @form = result.form
        set_context
        render :new, status: :unprocessable_content
      end
    end

    private

    def set_breadcrumbs
      override_breadcrumbs(
        { label: "Financial Reports", path: hotel_reports_path(current_hotel) },
        { label: "OTA Settlements", path: channel_settlements_hotel_reports_path(current_hotel) },
        { label: "Record Receipt" }
      )
    end

    def receipt_params
      params.fetch(:channel_settlement_receipt, {}).permit(
        :booking_source_id, :hotel_payment_method_id, :settlement_method, :amount,
        :currency, :received_at, :external_reference, :notes
      )
    end

    def set_context
      @booking_sources = BookingSource.where(
        id: current_hotel.channel_settlements.where(collection_by: "ota").select(:booking_source_id)
      ).order(:position, :label)
      @payment_methods = current_hotel.hotel_payment_methods.active.ordered.includes(:transaction_code)
      @allocations = outstanding_allocations
    end

    def outstanding_allocations
      current_hotel.channel_settlement_allocations
        .joins(:channel_settlement)
        .where(channel_settlements: { collection_by: "ota" })
        .includes(:channel_settlement_receipt_allocations, :booking, channel_settlement: :booking_source)
        .order("channel_settlements.created_at ASC", :id)
        .select { |allocation| remaining_amount(allocation).positive? }
    end

    def remaining_amount(allocation)
      allocation.expected_net_amount.to_d - allocation.channel_settlement_receipt_allocations.sum(&:amount).to_d
    end
    helper_method :remaining_amount

    def authorize_manage_ar_payments!
      raise Pundit::NotAuthorizedError unless current_user.has_permission?("manage_ar_payments", hotel: current_hotel)
    end
  end
end
