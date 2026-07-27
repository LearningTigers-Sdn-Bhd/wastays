# frozen_string_literal: true


module Folios
  module Payments
    class RecordTourismTaxPayment
      METADATA_SOURCE = "tourism_tax_check_in"

      def self.call(booking:, user:, options: {})
        new(booking: booking, user: user, options: options).call
      end

      def initialize(booking:, user:, options: {})
        @booking = booking
        @user = user
        @options = options
      end

      def call
        return success(existing_payment) if existing_payment.present?
        return success(nil) unless @booking.tourism_tax_collected?

        amount = @booking.tourism_tax_total
        return success(nil) unless amount.positive?
        return failure("Booking must have a folio before recording tourism tax payment.") if @booking.booking_folio.blank?

        result = Folios::Transactions::InsertTransaction.new(
          booking_folio: @booking.booking_folio,
          amount: amount,
          transaction_type: :payment,
          category: "cash",
          user: @user,
          description: "Tourism Tax collected at check-in",
          posting_date: @booking.hotel.current_business_date,
          options: posting_options.merge(
            posting_source: METADATA_SOURCE,
            metadata: (@options[:metadata] || {}).merge(
              source: METADATA_SOURCE,
              booking_id: @booking.id,
              tourism_tax: true,
              posted_by_user_id: @user&.id
            )
          )
        ).call

        return result unless result.success?

        @booking.update!(tourism_tax_collected: true) unless @booking.tourism_tax_collected?
        result
      end

      private

      def existing_payment
        return if @booking.booking_folio.blank?

        @existing_payment ||= @booking.booking_folio.folio_transactions.payment
          .where("metadata->>'source' = ?", METADATA_SOURCE)
          .first
      end

      def posting_options
        return @options unless @options[:override_night_audit]

        @options.reverse_merge(
          correction_reason: "tourism_tax_payment_on_retroactive_checkin",
          correction_note: @options[:reason].presence || "Record tourism tax collection while checking in on a closed business date."
        )
      end

      def success(transaction)
        Folios::Transactions::TransactionResult.success(transaction: transaction)
      end

      def failure(error)
        Folios::Transactions::TransactionResult.failure(error)
      end
    end
  end
end
