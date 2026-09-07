# frozen_string_literal: true

module HotelPortal
  module Folios
    class IndexQuery
      Collection = Data.define(:query) do
        def count
          query.filtered_count
        end

        def offset(value)
          Window.new(query:, offset: value)
        end
      end

      Window = Data.define(:query, :offset) do
        def limit(value)
          query.page(offset:, limit: value)
        end
      end

      FILTERS = %w[all open balance_due refund_due due_out closed adjusted review].freeze

      OPEN_SQL = "booking_folios.status = 'open'"
      CLOSED_SQL = "booking_folios.status = 'closed'"
      BALANCE_SQL = "COALESCE(folio_financials.balance, 0)"
      ADJUSTED_SQL = "COALESCE(folio_financials.adjusted, FALSE)"
      DUE_OUT_SQL = "bookings.check_out >= ? AND bookings.check_out < ?"
      CLOSED_TODAY_SQL = "booking_folios.updated_at >= ? AND booking_folios.updated_at < ?"
      UNSYNCED_REFUND_SQL = <<~SQL.squish
        refund_requests.status = 'completed'
        AND NOT EXISTS (
          SELECT 1
          FROM folio_transactions refund_transactions
          WHERE refund_transactions.booking_folio_id = booking_folios.id
            AND refund_transactions.transaction_type = 'payment'
            AND refund_transactions.metadata ->> 'refund_request_id' = refund_requests.id::text
            AND refund_transactions.amount = -refund_requests.refund_amount
        )
      SQL
      ATTENTION_SQL = "((#{OPEN_SQL} AND #{BALANCE_SQL} <> 0) OR #{UNSYNCED_REFUND_SQL})"

      SEARCH_SQL = <<~SQL.squish
        bookings.guest_name ILIKE :search
        OR bookings.confirmation_token ILIKE :search
        OR bookings.guest_email ILIKE :search
        OR bookings.guest_phone ILIKE :search
        OR CAST(booking_folios.folio_number AS TEXT) ILIKE :search
        OR CASE
          WHEN NULLIF(bookings.folio_account_reference, '') IS NOT NULL AND booking_folios.folio_sequence IS NOT NULL
            THEN bookings.folio_account_reference || '/' || booking_folios.folio_sequence::text
          WHEN NULLIF(bookings.folio_account_reference, '') IS NOT NULL THEN bookings.folio_account_reference
          ELSE COALESCE(booking_folios.folio_number::text, bookings.confirmation_token)
        END ILIKE :search
        OR EXISTS (
          SELECT 1 FROM booking_rooms
          WHERE booking_rooms.booking_id = bookings.id
            AND booking_rooms.room_number ILIKE :search
        )
      SQL

      def initialize(hotel:, query:, filter:, attention_only: false)
        @hotel = hotel
        @query = query.to_s.strip
        @filter = filter.to_s.presence_in(FILTERS) || "all"
        @attention_only = attention_only
      end

      def collection
        Collection.new(self)
      end

      def page(offset:, limit:)
        filtered_scope
          .select("booking_folios.*", "#{BALANCE_SQL} AS calculated_balance", "#{ADJUSTED_SQL} AS calculated_adjusted", "#{due_out_sql} AS calculated_due_out", "#{closed_today_sql} AS calculated_closed_today", "#{UNSYNCED_REFUND_SQL} AS calculated_unsynced_refund")
          .includes(booking: :booking_rooms)
          .offset(offset)
          .limit(limit)
          .to_a
      end

      def filtered_count
        @filtered_count ||= filtered_scope.count
      end

      def needs_attention_count
        @needs_attention_count ||= base_scope.where(ATTENTION_SQL).count
      end

      def summary_counts
        @summary_counts ||= aggregate_counts(base_scope, %w[open balance_due refund_due closed_today])
      end

      def filter_counts(filters)
        keys = filters.map(&:first)
        @filter_counts ||= aggregate_counts(scoped_scope, keys)
      end

      private

      attr_reader :hotel, :query, :filter, :attention_only

      def filtered_scope
        @filtered_scope ||= begin
          scope = scoped_scope
          scope = scope.where(SEARCH_SQL, search: search_pattern) if query.present?
          scope.where(condition_for(filter)).order(updated_at: :desc, id: :desc)
        end
      end

      def scoped_scope
        @scoped_scope ||= attention_only ? base_scope.where(ATTENTION_SQL) : base_scope
      end

      def base_scope
        @base_scope ||= hotel.booking_folios
          .joins(:booking)
          .joins("LEFT JOIN (#{transaction_totals.to_sql}) folio_financials ON folio_financials.booking_folio_id = booking_folios.id")
          .joins("LEFT JOIN refund_requests ON refund_requests.booking_id = bookings.id")
      end

      def transaction_totals
        FolioTransaction
          .select(:booking_folio_id)
          .select(<<~SQL.squish)
            SUM(
              CASE folio_transactions.transaction_type
              WHEN 'charge' THEN folio_transactions.amount
              WHEN 'payment' THEN -folio_transactions.amount
              WHEN 'adjustment' THEN folio_transactions.amount
              ELSE 0
              END
            ) AS balance,
            BOOL_OR(folio_transactions.transaction_type = 'adjustment') AS adjusted
          SQL
          .group(:booking_folio_id)
      end

      def aggregate_counts(scope, keys)
        selections = keys.map { |key| Arel.sql(count_filter_sql(key)) }
        values = scope.unscope(:select, :order).pick(*selections)
        values = [ values ] if selections.one?
        keys.zip(values || Array.new(keys.size, 0)).to_h
      end

      # The condition is bound before it reaches Arel.sql, so the aggregate
      # carries no raw value of its own.
      def count_filter_sql(key)
        condition, *binds = condition_for(key)
        sanitize([ "COUNT(*) FILTER (WHERE #{condition})", *binds ])
      end

      # Returns a where-style array: the SQL first, then any bind values.
      def condition_for(key)
        case key
        when "open" then [ OPEN_SQL ]
        when "balance_due" then [ "#{OPEN_SQL} AND #{BALANCE_SQL} > 0" ]
        when "refund_due" then [ "#{OPEN_SQL} AND #{BALANCE_SQL} < 0" ]
        when "due_out" then [ "#{OPEN_SQL} AND #{DUE_OUT_SQL}", *bounds(local_date_window) ]
        when "closed" then [ CLOSED_SQL ]
        when "closed_today" then [ "#{CLOSED_SQL} AND #{CLOSED_TODAY_SQL}", *bounds(business_day_window) ]
        when "adjusted" then [ ADJUSTED_SQL ]
        when "review" then [ UNSYNCED_REFUND_SQL ]
        else [ "TRUE" ]
        end
      end

      def due_out_sql
        @due_out_sql ||= sanitize([ DUE_OUT_SQL, *bounds(local_date_window) ])
      end

      def closed_today_sql
        @closed_today_sql ||= sanitize([ "#{CLOSED_SQL} AND #{CLOSED_TODAY_SQL}", *bounds(business_day_window) ])
      end

      def sanitize(statement)
        ActiveRecord::Base.sanitize_sql_array(statement)
      end

      def bounds(range)
        [ range.begin, range.end ]
      end

      def search_pattern
        "%#{ActiveRecord::Base.sanitize_sql_like(query)}%"
      end

      def local_date_window
        zone = hotel.hotel_time_zone
        start_at = zone.local(business_date.year, business_date.month, business_date.day)
        start_at...(start_at + 1.day)
      end

      def business_day_window
        @business_day_window ||= hotel.business_day_window_for(business_date)
      end

      def business_date
        @business_date ||= (hotel.current_business_date || hotel.business_date_for(Time.current)).to_date
      end
    end
  end
end
