# frozen_string_literal: true

require "ostruct"

module Folios
  class RecordRefund
    def self.call(refund_request:, user:, posting_date: Time.current.to_date, options: {})
      new(refund_request: refund_request, user: user, posting_date: posting_date, options: options).call
    end

    def initialize(refund_request:, user:, posting_date:, options: {})
      @refund_request = refund_request
      @booking = refund_request.booking
      @folio = @booking.booking_folio
      @user = user
      @posting_date = posting_date
      @options = options
    end

    def call
      return success(nil) unless @folio

      @folio.with_lock do
        return success(existing_refund_transaction) if existing_refund_transaction

        result = Folios::InsertTransaction.new(
          booking_folio: @folio,
          amount: -@refund_request.refund_amount.to_d,
          transaction_type: :payment,
          category: "refund",
          user: @user,
          description: "Refund completed",
          posting_date: @posting_date,
          options: merged_options
        ).call

        return failure(result.error) unless result.success?

        success(result.transaction)
      end
    end

    private

    def existing_refund_transaction
      @existing_refund_transaction ||= @folio.folio_transactions.payment
        .where("metadata->>'refund_request_id' = ?", @refund_request.id.to_s)
        .first
    end

    def merged_options
      metadata = (@options[:metadata] || {}).merge(refund_request_id: @refund_request.id)
      @options.merge(metadata: metadata)
    end

    def success(transaction)
      OpenStruct.new(success?: true, transaction: transaction)
    end

    def failure(error)
      OpenStruct.new(success?: false, error: error)
    end
  end
end
