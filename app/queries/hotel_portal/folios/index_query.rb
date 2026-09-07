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
          .select("booking_folios.*", "#{balance_sql} AS calculated_balance", "#{adjusted_sql} AS calculated_adjusted", "#{due_out_sql} AS calculated_due_out", "#{closed_today_sql} AS calculated_closed_today", "#{unsynced_refund_sql} AS calculated_unsynced_refund")
          .includes(booking: :booking_rooms)
          .offset(offset)
          .limit(limit)
          .to_a
      end

      def filtered_count
        @filtered_count ||= filtered_scope.count
      end

      def needs_attention_count
        @needs_attention_count ||= base_scope.where(attention_sql).count
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
          scope = scope.where(search_sql, search: search_pattern) if query.present?
          scope.where(condition_for(filter)).order(updated_at: :desc, id: :desc)
        end
      end

      def scoped_scope
        @scoped_scope ||= attention_only ? base_scope.where(attention_sql) : base_scope
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
        selections = keys.map do |key|
          condition = key == "closed_today" ? closed_today_sql : condition_for(key)
          Arel.sql("COUNT(*) FILTER (WHERE #{condition})")
        end
        values = scope.unscope(:select, :order).pick(*selections)
        values = [ values ] if selections.one?
        keys.zip(values || Array.new(keys.size, 0)).to_h
      end

      def condition_for(key)
        case key
        when "open" then "booking_folios.status = 'open'"
        when "balance_due" then "booking_folios.status = 'open' AND #{balance_sql} > 0"
        when "refund_due" then "booking_folios.status = 'open' AND #{balance_sql} < 0"
        when "due_out" then "booking_folios.status = 'open' AND #{due_out_sql}"
        when "closed" then "booking_folios.status = 'closed'"
        when "adjusted" then adjusted_sql
        when "review" then unsynced_refund_sql
        else "TRUE"
        end
      end

      def attention_sql
        @attention_sql ||= "((booking_folios.status = 'open' AND #{balance_sql} <> 0) OR #{unsynced_refund_sql})"
      end

      def balance_sql
        "COALESCE(folio_financials.balance, 0)"
      end

      def adjusted_sql
        "COALESCE(folio_financials.adjusted, FALSE)"
      end

      def due_out_sql
        @due_out_sql ||= range_sql("bookings.check_out", local_date_window)
      end

      def closed_today_sql
        @closed_today_sql ||= "booking_folios.status = 'closed' AND #{range_sql('booking_folios.updated_at', business_day_window)}"
      end

      def unsynced_refund_sql
        @unsynced_refund_sql ||= <<~SQL.squish
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
      end

      def search_sql
        <<~SQL.squish
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
      end

      def search_pattern
        "%#{ActiveRecord::Base.sanitize_sql_like(query)}%"
      end

      def range_sql(column, range)
        connection = ActiveRecord::Base.connection
        "#{column} >= #{connection.quote(range.begin)} AND #{column} < #{connection.quote(range.end)}"
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
