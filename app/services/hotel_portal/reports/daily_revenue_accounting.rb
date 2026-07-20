# frozen_string_literal: true

module HotelPortal
  module Reports
    class DailyRevenueAccounting
      ZERO_BUCKET = {
        accommodation: 0.to_d,
        other_charges: 0.to_d,
        tax: 0.to_d,
        adjustments: 0.to_d,
        gateway_payment: 0.to_d,
        cash_payment: 0.to_d,
        booking_payment: 0.to_d,
        refund: 0.to_d
      }.freeze

      def initialize(transactions)
        @transactions = transactions
      end

      def bucket_for(transaction)
        amount = transaction.amount.to_d

        case transaction.transaction_type
        when "charge"
          key = case transaction.category
          when "accommodation" then :accommodation
          when "tax" then :tax
          else :other_charges
          end
          { key => amount }
        when "payment"
          key = case transaction.category
          when "refund" then :refund
          when "gateway_payment" then :gateway_payment
          when "booking_payment" then :booking_payment
          else :cash_payment
          end
          { key => amount }
        when "adjustment"
          { adjustments: amount }
        else
          {}
        end
      end

      def totals
        with_derived_fields(sum_buckets(@transactions))
      end

      def sum_buckets(transactions)
        transactions.each_with_object(ZERO_BUCKET.dup) do |transaction, bucket|
          bucket_for(transaction).each { |key, amount| bucket[key] += amount }
        end
      end

      def with_derived_fields(bucket)
        total_charges = bucket.values_at(:accommodation, :other_charges, :tax).sum
        total_payments = bucket.values_at(:gateway_payment, :cash_payment, :booking_payment).sum

        bucket.merge(
          total_charges: total_charges,
          net_revenue: total_charges + bucket[:adjustments],
          total_payments: total_payments,
          net_payments: total_payments + bucket[:refund]
        )
      end
    end
  end
end
