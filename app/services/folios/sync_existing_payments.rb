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

          amount = pt.amount_subunits.to_d / 100.0
          result = Folios::InsertTransaction.new(
            booking_folio: @folio,
            amount: amount,
            transaction_type: :payment,
            category: "advance_deposit",
            user: posting_user,
            description: "Advance deposit from booking quote payment via #{pt.gateway} (#{pt.external_reference})",
            posting_date: pt.captured_at&.to_date || pt.created_at.to_date,
            options: override_options.merge({
              posting_source: "gateway_payment",
              metadata: {
                payment_transaction_id: pt.id,
                source: "booking_quote",
                applied_as: "advance_deposit"
              }
            })
          ).call

          next if result.success? || already_recorded?(pt)

          raise "Failed to sync folio payment: #{result.error}"
        end
      end
    end

    private

    def override_options
      return @options unless @options[:override_night_audit]

      @options.reverse_merge(
        correction_reason: "payment_sync_on_retroactive_checkin",
        correction_note: "Sync captured payment while opening folio on a closed business date."
      )
    end

    def posting_user
      @options[:override_night_audit] ? @user : nil
    end

    def already_recorded?(pt)
      @folio.folio_transactions.payment.where("metadata->>'payment_transaction_id' = ?", pt.id.to_s).exists?
    end
  end
end
