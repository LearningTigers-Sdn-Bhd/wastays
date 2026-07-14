# frozen_string_literal: true

module HotelPortal
  module Reports
    class DailyRevenueReport
      SOURCE_LABELS = {
        "walk_in" => "Walk-in",
        "agoda" => "Agoda",
        "whatsapp" => "WhatsApp",
        "corporate" => "Corporate",
        "internal" => "Direct"
      }.freeze

      AGENT_ACCOUNT_TYPES = %w[travel_agent airline].freeze

      Result = Struct.new(:start_date, :end_date, :totals, :rows, :source_rows, keyword_init: true)

      def initialize(hotel:, start_date:, end_date:, date_preset: nil)
        @hotel = hotel
        @start_date = start_date.to_date
        @end_date = end_date.to_date
        @date_preset = date_preset.to_s
      end

      def call
        # Query all transactions within the date range
        transactions = FolioTransaction.joins(booking_folio: :booking)
                         .left_outer_joins(:reversal_of_transaction)
                         .where(bookings: { hotel_id: @hotel.id })
                         .where(posting_date: @start_date..@end_date)
                         .select(
                           "folio_transactions.*",
                           "bookings.source as booking_source",
                           "bookings.id as booking_id",
                           "reversal_of_transactions_folio_transactions.category as reversed_category"
                         )

        # Build daily stats
        daily_stats = Hash.new do |h, k|
          h[k] = {
            booking_ids: Set.new,
            accommodation: 0.to_d,
            tax: 0.to_d,
            other_charges: 0.to_d,
            discount: 0.to_d,
            gateway_payment: 0.to_d,
            cash_payment: 0.to_d,
            booking_payment: 0.to_d,
            agent_bank_transfer: 0.to_d,
            corporate_bank_transfer: 0.to_d,
            refund: 0.to_d
          }
        end

        source_stats = Hash.new do |h, k|
          h[k] = {
            booking_ids: Set.new,
            accommodation: 0.to_d,
            tax: 0.to_d,
            other_charges: 0.to_d,
            discount: 0.to_d,
            gateway_payment: 0.to_d,
            cash_payment: 0.to_d,
            booking_payment: 0.to_d,
            refund: 0.to_d
          }
        end

        transactions.each do |tx|
          date = tx.posting_date
          source = normalize_source(tx.booking_source)
          amount = tx.amount.to_d.abs
          booking_id = tx.booking_id

          daily_stats[date][:booking_ids] << booking_id
          source_stats[source][:booking_ids] << booking_id

          case tx.transaction_type
          when "charge"
            case tx.category
            when "accommodation"
              daily_stats[date][:accommodation] += amount
              source_stats[source][:accommodation] += amount
            when "tax"
              daily_stats[date][:tax] += amount
              source_stats[source][:tax] += amount
            else
              daily_stats[date][:other_charges] += amount
              source_stats[source][:other_charges] += amount
            end
          when "payment"
            case tx.category
            when "gateway_payment"
              daily_stats[date][:gateway_payment] += amount
              source_stats[source][:gateway_payment] += amount
            when "cash"
              daily_stats[date][:cash_payment] += amount
              source_stats[source][:cash_payment] += amount
            when "booking_payment"
              daily_stats[date][:booking_payment] += amount
              source_stats[source][:booking_payment] += amount
            when "refund"
              daily_stats[date][:refund] += amount
              source_stats[source][:refund] += amount
            end
          when "adjustment"
            if tx.category == "discount" || tx.reversed_category == "discount"
              daily_stats[date][:discount] += amount
              source_stats[source][:discount] += amount
            end
          end
        end

        ArPayment.where(hotel_id: @hotel.id, payment_method: "bank_transfer", received_at: @start_date..@end_date)
          .joins(:hotel_corporate_account)
          .select("ar_payments.*, hotel_corporate_accounts.account_type AS payer_account_type")
          .each do |payment|
            bucket = AGENT_ACCOUNT_TYPES.include?(payment.payer_account_type) ? :agent_bank_transfer : :corporate_bank_transfer
            daily_stats[payment.received_at][bucket] += payment.amount.to_d
          end

        rows = (@start_date..@end_date).map do |date|
          stats = daily_stats[date]
          total_charges = stats[:accommodation] + stats[:tax] + stats[:other_charges]
          total_payments = stats[:gateway_payment] + stats[:cash_payment] + stats[:booking_payment] + stats[:agent_bank_transfer] + stats[:corporate_bank_transfer]
          net_amount = total_payments - stats[:refund]

          {
            date: date,
            booking_count: stats[:booking_ids].size,
            accommodation: stats[:accommodation].round(2),
            other_charges: stats[:other_charges].round(2),
            tax: stats[:tax].round(2),
            total_charges: total_charges.round(2),
            discount: stats[:discount].round(2),
            gateway_payment: stats[:gateway_payment].round(2),
            cash_payment: stats[:cash_payment].round(2),
            booking_payment: stats[:booking_payment].round(2),
            agent_bank_transfer: stats[:agent_bank_transfer].round(2),
            corporate_bank_transfer: stats[:corporate_bank_transfer].round(2),
            total_payments: total_payments.round(2),
            refund: stats[:refund].round(2),
            net_amount: net_amount.round(2)
          }
        end

        rows = monthly? ? aggregate_monthly(rows) : rows

        source_rows = source_stats.map do |source, stats|
          total_charges = stats[:accommodation] + stats[:tax] + stats[:other_charges]
          total_payments = stats[:gateway_payment] + stats[:cash_payment] + stats[:booking_payment]
          net_amount = total_payments - stats[:refund]

          {
            source: source,
            booking_count: stats[:booking_ids].size,
            accommodation: stats[:accommodation].round(2),
            other_charges: stats[:other_charges].round(2),
            tax: stats[:tax].round(2),
            total_charges: total_charges.round(2),
            discount: stats[:discount].round(2),
            gateway_payment: stats[:gateway_payment].round(2),
            cash_payment: stats[:cash_payment].round(2),
            booking_payment: stats[:booking_payment].round(2),
            total_payments: total_payments.round(2),
            refund: stats[:refund].round(2),
            net_amount: net_amount.round(2)
          }
        end.sort_by { |row| -row[:total_charges] }

        totals = {
          booking_count: transactions.map(&:booking_id).uniq.size,
          accommodation: rows.sum { |r| r[:accommodation] },
          other_charges: rows.sum { |r| r[:other_charges] },
          tax: rows.sum { |r| r[:tax] },
          total_charges: rows.sum { |r| r[:total_charges] },
          discount: rows.sum { |r| r[:discount] },
          gateway_payment: rows.sum { |r| r[:gateway_payment] },
          cash_payment: rows.sum { |r| r[:cash_payment] },
          booking_payment: rows.sum { |r| r[:booking_payment] },
          agent_bank_transfer: rows.sum { |r| r[:agent_bank_transfer] },
          corporate_bank_transfer: rows.sum { |r| r[:corporate_bank_transfer] },
          total_payments: rows.sum { |r| r[:total_payments] },
          refund: rows.sum { |r| r[:refund] },
          net_amount: rows.sum { |r| r[:net_amount] }
        }

        Result.new(
          start_date: @start_date,
          end_date: @end_date,
          totals: totals,
          rows: rows,
          source_rows: source_rows
        )
      end

      private

      def monthly?
        @date_preset == "this_year"
      end

      def aggregate_monthly(rows)
        rows.group_by { |row| row[:date].beginning_of_month }
            .map do |month, month_rows|
          total_charges = month_rows.sum { |row| row[:total_charges].to_d }
          total_payments = month_rows.sum { |row| row[:total_payments].to_d }

          {
            date: month,
            booking_count: month_rows.sum { |row| row[:booking_count].to_i },
            accommodation: month_rows.sum { |row| row[:accommodation].to_d }.round(2),
            other_charges: month_rows.sum { |row| row[:other_charges].to_d }.round(2),
            tax: month_rows.sum { |row| row[:tax].to_d }.round(2),
            total_charges: total_charges.round(2),
            discount: month_rows.sum { |row| row[:discount].to_d }.round(2),
            gateway_payment: month_rows.sum { |row| row[:gateway_payment].to_d }.round(2),
            cash_payment: month_rows.sum { |row| row[:cash_payment].to_d }.round(2),
            booking_payment: month_rows.sum { |row| row[:booking_payment].to_d }.round(2),
            agent_bank_transfer: month_rows.sum { |row| row[:agent_bank_transfer].to_d }.round(2),
            corporate_bank_transfer: month_rows.sum { |row| row[:corporate_bank_transfer].to_d }.round(2),
            total_payments: total_payments.round(2),
            refund: month_rows.sum { |row| row[:refund].to_d }.round(2),
            net_amount: month_rows.sum { |row| row[:net_amount].to_d }.round(2)
          }
        end
      end

      def normalize_source(source)
        source_key = source.to_s.strip
        source_key = "unknown" if source_key.empty?
        SOURCE_LABELS[source_key] || source_key.titleize.presence || "Others"
      end
    end
  end
end
