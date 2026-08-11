# frozen_string_literal: true

module HotelPortal
  class ChannelSettlementReceiptsController < ReportsBaseController
    ALLOCATION_LIMIT = 200

    before_action :authorize_manage_ar_payments!
    before_action :set_breadcrumbs

    def new
      set_context
      @form = HotelPortal::ChannelSettlementReceiptForm.new(
        booking_source_id: @context_source_id,
        currency: @context_currency,
        settlement_method: "bank_transfer",
        received_at: Time.current.in_time_zone(current_hotel.hotel_time_zone)
      )
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
        { label: "Financial", path: hotel_reports_path(current_hotel) },
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
      pairs = outstanding_scope
        .where("channel_settlements.currency = channel_settlement_allocations.currency")
        .distinct.pluck("channel_settlements.booking_source_id", "channel_settlement_allocations.currency")
      source_ids = pairs.map(&:first).uniq
      @booking_sources = BookingSource.where(id: source_ids).order(:position, :label)
      @context_source_id = valid_source_id(source_ids)
      @currencies = pairs.filter_map { |source_id, currency| currency if source_id == @context_source_id }.uniq.sort
      @context_currency = valid_currency
      @payment_methods = current_hotel.hotel_payment_methods.active.ordered.includes(:transaction_code)
      @allocation_search = params[:allocation_search].to_s.strip
      @allocations = scoped_allocations.limit(ALLOCATION_LIMIT + 1).to_a
      @allocation_limit_reached = @allocations.length > ALLOCATION_LIMIT
      @allocations = @allocations.first(ALLOCATION_LIMIT)
    end

    def valid_source_id(source_ids)
      requested = params[:booking_source_id].presence || @form&.booking_source_id
      requested = requested.to_i if requested.present?
      source_ids.include?(requested) ? requested : @booking_sources.first&.id
    end

    def valid_currency
      requested = params[:currency].presence || @form&.currency
      return requested if @currencies.include?(requested)
      return current_hotel.default_currency if @currencies.include?(current_hotel.default_currency)

      @currencies.first
    end

    def scoped_allocations
      scope = outstanding_scope
        .joins(:channel_settlement, :booking)
        .where(
          channel_settlements: { booking_source_id: @context_source_id, currency: @context_currency },
          channel_settlement_allocations: { currency: @context_currency }
        )
      if @allocation_search.present?
        pattern = "%#{ActiveRecord::Base.sanitize_sql_like(@allocation_search)}%"
        scope = scope.where(
          "channel_settlements.channel_manager_reference ILIKE :pattern OR bookings.confirmation_token ILIKE :pattern",
          pattern:
        )
      end
      scope.includes(:channel_settlement_receipt_allocations, :booking, channel_settlement: :booking_source)
        .order("channel_settlements.created_at ASC", :id)
    end

    def outstanding_scope
      current_hotel.channel_settlement_allocations
        .joins(:channel_settlement)
        .where(channel_settlements: { collection_by: "ota" })
        .where(<<~SQL.squish)
          channel_settlement_allocations.expected_net_amount > COALESCE(
            (SELECT SUM(receipt_allocations.amount)
             FROM channel_settlement_receipt_allocations receipt_allocations
             WHERE receipt_allocations.channel_settlement_allocation_id = channel_settlement_allocations.id), 0
          )
        SQL
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
