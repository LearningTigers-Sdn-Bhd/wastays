# frozen_string_literal: true

module HotelPortal
  module Reports
    class DailyRevenueAccounting
      ZERO_BUCKET = {
        accommodation: 0.to_d,
        room_fees: 0.to_d,
        other_charges: 0.to_d,
        tax: 0.to_d,
        adjustments: 0.to_d
      }.freeze

      ROOM_FEE_CATEGORIES = %w[no_show_charge early_departure_charge late_checkout_charge cancellation_charge].freeze

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
          when *ROOM_FEE_CATEGORIES then :room_fees
          else :other_charges
          end
          { key => amount }
        when "adjustment"
          { adjustments: amount }
        else
          {}
        end
      end

      def tax_charge?(transaction)
        transaction.transaction_type == "charge" && transaction.category == "tax"
      end

      def self.extra_charge?(transaction)
        transaction.transaction_type == "charge" && !(%w[accommodation tax] + ROOM_FEE_CATEGORIES).include?(transaction.category)
      end

      def extra_charge?(transaction) = self.class.extra_charge?(transaction)

      def tax_name_for(transaction)
        transaction.transaction_code_name_snapshot.presence ||
          transaction.metadata.to_h.dig("tax_line", "name").presence || "Tax"
      end

      def item_name_for(transaction)
        transaction.transaction_code_name_snapshot.presence || transaction.category.humanize
      end

      # A tax line keeps the id of its charge in metadata, even when routing moved it to another folio.
      def parent_id_for(transaction)
        transaction.parent_transaction_id || transaction.metadata.to_h["parent_folio_transaction_id"]
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
        total_charges = bucket.values_at(:accommodation, :room_fees, :other_charges, :tax).sum

        bucket.merge(
          total_charges: total_charges,
          net_revenue: total_charges + bucket[:adjustments]
        )
      end
    end
  end
end
