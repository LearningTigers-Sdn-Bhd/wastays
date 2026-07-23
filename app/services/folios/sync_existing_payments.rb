# frozen_string_literal: true

module Folios
  class SyncExistingPayments
    def self.call(folio:, user:, options: {})
      new(folio: folio, user: user, options: options).call
    end

    def initialize(folio:, user:, options: {})
      @folio = folio
      @booking = folio.booking
      @user = user
      @options = options
    end

    def call
      @folio.with_lock do
        @booking.payment_transactions.where(status: "captured").find_each do |pt|
          next if already_recorded?(pt)

          posting_date = @booking.hotel.current_business_date
          amount = pt.amount_subunits.to_d / 100.0

          transaction_options = override_options.merge({
            posting_source: payment_posting_source,
            system_posting: true,
            metadata: {
              payment_transaction_id: pt.id,
              source: "booking_quote",
              applied_as: "booking_payment"
            }
          })

          if @booking.hotel.date_closed?(posting_date) || posting_date < @booking.hotel.current_business_date
            transaction_options[:override_night_audit] = true
            transaction_options[:correction_reason] ||= "payment_sync_on_closed_date"
            transaction_options[:correction_note] ||= "Automated sync of captured payment on a closed business date."
          end

          result = Folios::InsertTransaction.new(
            booking_folio: @folio,
            amount: amount,
            transaction_type: :payment,
            category: "booking_payment",
            user: posting_user(transaction_options),
            description: payment_description(pt),
            posting_date: posting_date,
            options: transaction_options
          ).call

          next if result.success? || already_recorded?(pt)

          raise "Failed to sync folio payment: #{result.error}"
        end
      end
    end

    private

    def payment_description(payment_transaction)
      reference = payment_transaction.external_reference.presence

      [ "Booking payment via #{payment_transaction.gateway}", ("(#{reference})" if reference) ].compact.join(" ")
    end

    def override_options
      return @options unless @options[:override_night_audit]

      @options.reverse_merge(
        correction_reason: "payment_sync_on_retroactive_checkin",
        correction_note: "Sync captured payment while opening folio on a closed business date."
      )
    end

    def posting_user(options = @options)
      options[:override_night_audit] ? @user : nil
    end

    def payment_posting_source
      @options[:posting_source].presence || "gateway_payment"
    end

    def already_recorded?(pt)
      @folio.folio_transactions.payment.where("metadata->>'payment_transaction_id' = ?", pt.id.to_s).exists?
    end
  end
end
