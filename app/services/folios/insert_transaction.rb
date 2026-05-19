# frozen_string_literal: true

require "ostruct"

module Folios
  class InsertTransaction
    def initialize(booking_folio:, amount:, transaction_type:, category:, user:, description: nil, posting_date: nil, options: {})
      @booking_folio = booking_folio
      @amount = amount.to_d
      @transaction_type = transaction_type.to_s
      @category = category.to_s
      @user = user
      @description = description
      @posting_date = posting_date || Time.current.to_date
      @options = options
    end

    def call
      @booking_folio.with_lock do
        @booking_folio.reload

        if @booking_folio.status == "closed" && !@options[:override_closed_folio]
          return failure("Folio is closed. Please provide an override flag to post to a closed folio.")
        end

        if NightAudit.closed_for_date?(@booking_folio.booking.hotel_id, @posting_date)
          unless @options[:override_night_audit]
            return failure("The business date #{@posting_date} is already closed. Please provide an override flag to post to a closed date.")
          end
        end

        transaction = @booking_folio.folio_transactions.build(
          amount: @amount,
          transaction_type: @transaction_type,
          category: @category,
          user: @user,
          description: @description,
          posting_date: @posting_date,
          posted_at: @options[:posted_at] || Time.current,
          currency: @options[:currency] || @booking_folio.booking.currency,
          reversal_of_transaction: @options[:reversal_of_transaction],
          correction_reason: @options[:correction_reason],
          correction_note: @options[:correction_note],
          metadata: @options[:metadata] || {}
        )

        if transaction.save
          success(transaction)
        else
          failure(transaction.errors.full_messages.to_sentence)
        end
      end
    rescue StandardError => e
      failure(e.message)
    end

    private

    def success(transaction)
      OpenStruct.new(success?: true, transaction: transaction)
    end

    def failure(error)
      OpenStruct.new(success?: false, error: error)
    end
  end
end
