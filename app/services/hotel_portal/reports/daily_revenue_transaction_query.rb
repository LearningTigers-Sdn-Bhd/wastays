# frozen_string_literal: true

module HotelPortal
  module Reports
    class DailyRevenueTransactionQuery
      FILTER_KEYS = %w[q transaction_type category transaction_code_id posting_source reversal_status].freeze

      attr_reader :filters

      def initialize(hotel:, start_date:, end_date:, filters: {})
        @hotel = hotel
        @start_date = start_date.to_date
        @end_date = end_date.to_date
        @filters = filters.to_h.stringify_keys.slice(*FILTER_KEYS).transform_values { |value| value.to_s.strip }.compact_blank
      end

      def call
        scope = base_scope
        scope = apply_search(scope)
        scope = apply_transaction_type(scope)
        scope = apply_category(scope)
        scope = apply_transaction_code(scope)
        scope = apply_posting_source(scope)
        scope = apply_reversal_status(scope)

        scope.order(Arel.sql(
          "folio_transactions.posting_date DESC, folio_transactions.posted_at DESC NULLS LAST, folio_transactions.id DESC"
        ))
      end

      private

      def base_scope
        FolioTransaction
          .joins(booking_folio: :booking)
          .left_outer_joins(:transaction_code)
          .where(bookings: { hotel_id: @hotel.id })
          .where(posting_date: @start_date..@end_date)
          .includes(
            :transaction_code,
            :user,
            booking_folio: [ :booking_room, { booking: :booking_rooms } ]
          )
      end

      def apply_search(scope)
        return scope unless filters["q"].present?

        term = "%#{ActiveRecord::Base.sanitize_sql_like(filters['q'])}%"
        scope.where(
          <<~SQL.squish,
            bookings.guest_name ILIKE :term OR
            bookings.confirmation_token ILIKE :term OR
            booking_folios.folio_number::text ILIKE :term OR
            folio_transactions.description ILIKE :term OR
            transaction_codes.code ILIKE :term OR
            transaction_codes.name ILIKE :term
          SQL
          term: term
        )
      end

      def apply_transaction_type(scope)
        return scope unless filters["transaction_type"].present?

        scope.where(transaction_type: filters["transaction_type"])
      end

      def apply_category(scope)
        return scope unless filters["category"].present?

        scope.where(category: filters["category"])
      end

      def apply_transaction_code(scope)
        return scope unless filters["transaction_code_id"].present?

        scope.where(transaction_code_id: filters["transaction_code_id"])
      end

      def apply_posting_source(scope)
        return scope unless filters["posting_source"].present?

        scope.where("folio_transactions.metadata ->> 'posting_source' = ?", filters["posting_source"])
      end

      def apply_reversal_status(scope)
        case filters["reversal_status"]
        when "original" then scope.where(reversal_of_transaction_id: nil, voided_by_transaction_id: nil)
        when "reversed" then scope.where.not(voided_by_transaction_id: nil)
        when "reversal" then scope.where.not(reversal_of_transaction_id: nil)
        else scope
        end
      end
    end
  end
end
