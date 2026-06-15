# frozen_string_literal: true

require "ostruct"

module Folios
  class RecordRefund
    def self.call(refund_request:, user:, posting_date: nil, options: {})
      new(refund_request: refund_request, user: user, posting_date: posting_date, options: options).call
    end

    def initialize(refund_request:, user:, posting_date:, options: {})
      @refund_request = refund_request
      @booking = refund_request.booking
      @folio = @booking.booking_folio
      @user = user
      @posting_date = posting_date || @booking.hotel.current_business_date
      @options = options
    end

    def call
      return success(nil) unless @folio

      @folio.with_lock do
        return success(existing_refund_transaction) if existing_refund_transaction

        target_date = @posting_date
        description = "Refund completed"
        options = merged_options

        if @booking.hotel.date_closed?(target_date) || target_date < @booking.hotel.current_business_date
          options[:override_night_audit] = true
          options[:system_posting] = true
          options[:correction_reason] ||= "refund_on_closed_date"
          options[:correction_note] ||= "Automated recording of refund on a closed business date."
        end

        result = Folios::InsertTransaction.new(
          booking_folio: @folio,
          amount: -@refund_request.refund_amount.to_d,
          transaction_type: :payment,
          category: "refund",
          user: @user,
          description: description,
          posting_date: target_date,
          options: options
        ).call

        unless result.success?
          existing_transaction = existing_refund_transaction(force_reload: true)
          return success(existing_transaction) if existing_transaction

          return failure(result.error)
        end

        success(result.transaction)
      end
    rescue ActiveRecord::RecordNotUnique
      existing_transaction = existing_refund_transaction(force_reload: true)
      existing_transaction ? success(existing_transaction) : failure("Refund was already recorded but could not be loaded")
    end

    private

    def existing_refund_transaction(force_reload: false)
      @existing_refund_transaction = nil if force_reload
      @existing_refund_transaction ||= @folio.folio_transactions.payment
        .where("metadata->>'refund_request_id' = ?", @refund_request.id.to_s)
        .first
    end

    def merged_options
      metadata = (@options[:metadata] || {}).merge(refund_request_id: @refund_request.id)
      @options.merge(posting_source: @options[:posting_source] || "gateway_refund", metadata: metadata)
    end

    def success(transaction)
      OpenStruct.new(success?: true, transaction: transaction)
    end

    def failure(error)
      OpenStruct.new(success?: false, error: error)
    end
  end
end
