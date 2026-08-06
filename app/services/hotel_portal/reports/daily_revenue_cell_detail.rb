# frozen_string_literal: true

module HotelPortal
  module Reports
    class DailyRevenueCellDetail
      AGENT_ACCOUNT_TYPES = %w[travel_agent airline].freeze

      CATEGORY_LABELS = {
        "accommodation" => "Accommodation",
        "other_charges" => "Other Charges",
        "tax" => "Tax",
        "discount" => "Discount",
        "gateway_payment" => "Online Payment",
        "cash_payment" => "Cash Payment",
        "booking_payment" => "Deposit",
        "agent_bank_transfer" => "Agent Bank Transfer",
        "corporate_bank_transfer" => "Corporate Bank Transfer",
        "refund" => "Refund"
      }.freeze

      BANK_TRANSFER_CATEGORIES = %w[agent_bank_transfer corporate_bank_transfer].freeze

      Entry = Struct.new(:date, :description, :amount, :currency, :booking_reference, :folio_reference, :source_label, keyword_init: true)
      Result = Struct.new(:category, :category_label, :start_date, :end_date, :entries, keyword_init: true)

      def initialize(hotel:, start_date:, end_date:, category:)
        @hotel = hotel
        @start_date = start_date.to_date
        @end_date = end_date.to_date
        @category = category.to_s
      end

      def call
        Result.new(
          category: @category,
          category_label: CATEGORY_LABELS.fetch(@category, @category.humanize),
          start_date: @start_date,
          end_date: @end_date,
          entries: entries
        )
      end

      private

      def entries
        return [] unless CATEGORY_LABELS.key?(@category)

        BANK_TRANSFER_CATEGORIES.include?(@category) ? bank_transfer_entries : transaction_entries
      end

      def transaction_entries
        transactions = FolioTransaction.joins(booking_folio: :booking)
          .left_outer_joins(:reversal_of_transaction)
          .where(bookings: { hotel_id: @hotel.id })
          .where(posting_date: @start_date..@end_date)
          .select(
            "folio_transactions.*",
            "bookings.confirmation_token AS booking_confirmation_token",
            "bookings.source AS booking_source",
            "reversal_of_transactions_folio_transactions.category AS reversed_category"
          )
          .includes(booking_folio: :booking)
          .order(:posting_date, :created_at)

        transactions.filter_map do |tx|
          next unless matches_category?(tx)

          Entry.new(
            date: tx.posting_date,
            description: tx.description,
            amount: tx.amount.to_d.abs,
            currency: tx.currency,
            booking_reference: tx.booking_confirmation_token,
            folio_reference: tx.booking_folio.folio_reference_display,
            source_label: normalize_source(tx.booking_source)
          )
        end
      end

      def matches_category?(tx)
        case @category
        when "accommodation"
          tx.transaction_type == "charge" && tx.category == "accommodation"
        when "tax"
          tx.transaction_type == "charge" && tx.category == "tax"
        when "other_charges"
          tx.transaction_type == "charge" && !%w[accommodation tax].include?(tx.category)
        when "discount"
          tx.transaction_type == "adjustment" && (tx.category == "discount" || tx.reversed_category == "discount")
        when "gateway_payment"
          tx.transaction_type == "payment" && tx.category == "gateway_payment"
        when "cash_payment"
          tx.transaction_type == "payment" && tx.category == "cash"
        when "booking_payment"
          tx.transaction_type == "payment" && tx.category == "booking_payment"
        when "refund"
          tx.transaction_type == "payment" && tx.category == "refund"
        else
          false
        end
      end

      def bank_transfer_entries
        ArPayment.where(hotel_id: @hotel.id, payment_method: "bank_transfer", received_at: @start_date..@end_date)
          .joins(hotel_corporate_account: :corporate_account)
          .select("ar_payments.*, hotel_corporate_accounts.account_type AS payer_account_type, accounts.name AS payer_account_name")
          .order(:received_at)
          .filter_map do |payment|
            is_agent = AGENT_ACCOUNT_TYPES.include?(payment.payer_account_type)
            next if @category == "agent_bank_transfer" && !is_agent
            next if @category == "corporate_bank_transfer" && is_agent

            Entry.new(
              date: payment.received_at,
              description: "Bank transfer · #{payment.reference_number}",
              amount: payment.amount.to_d,
              currency: payment.currency,
              booking_reference: nil,
              folio_reference: nil,
              source_label: payment.payer_account_name
            )
          end
      end

      def normalize_source(source)
        BookingSourceLabel.normalize(source)
      end
    end
  end
end
