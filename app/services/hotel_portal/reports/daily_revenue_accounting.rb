# frozen_string_literal: true

module HotelPortal
  module Reports
    class DailyRevenueAccounting
      ZERO_BUCKET = {
        accommodation: 0.to_d,
        other_charges: 0.to_d,
        tax: 0.to_d,
        adjustments: 0.to_d
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

        bucket.merge(
          total_charges: total_charges,
          net_revenue: total_charges + bucket[:adjustments]
        )
      end
    end
  end
end
