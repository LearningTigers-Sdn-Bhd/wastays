# frozen_string_literal: true

require "set"

module HotelPortal
  module Reports
    class BookingPerformanceReport
      GROUPINGS = %w[booking_date source fund_collector status currency].freeze
      DEFAULT_GROUPING = "booking_date"
      GROUPING_LABELS = {
        "booking_date" => [ "Booking date", "calendar-days" ],
        "source" => [ "Source", "radio" ],
        "fund_collector" => [ "Collected by", "wallet" ],
        "status" => [ "Status", "list-checks" ],
        "currency" => [ "Currency", "coins" ]
      }.freeze
      COLLECTOR_ORDER = %w[wastays hotel].freeze
      OTA_COLLECTOR_PREFIX = "ota:"
      UNKNOWN_COLLECTOR_RANK = 99

      Row = Data.define(
        :booking_id, :booked_on, :booking_number, :confirmation_code, :guest_name,
        :status, :status_label, :payment_status, :payment_status_label,
        :check_in, :check_out, :source, :source_label,
        :fund_collector, :fund_collector_label,
        :gross, :taxes, :commission, :net, :currency
      )
      Group = Data.define(:key, :label, :rows, :count, :currency_totals)

      attr_reader :group_by, :filter_options, :rows, :start_date, :end_date

      def initialize(hotel:, bookings: nil, group_by: nil, date_preset: nil, filters: {}, rows: nil,
                     start_date: nil, end_date: nil)
        @hotel = hotel
        @group_by = group_by.to_s.presence_in(GROUPINGS) || DEFAULT_GROUPING
        @date_preset = date_preset.to_s
        @start_date = start_date&.to_date
        @end_date = end_date&.to_date
        @filter_options = bookings ? build_filter_options(bookings) : empty_filter_options
        @rows = rows || select_collectors(
          build_rows(apply_filters(bookings, filters)), filters[:fund_collectors]
        )
      end

      def groups
        @groups ||= rows.group_by { |row| group_key(row) }
          .map do |key, group_rows|
            Group.new(
              key:,
              label: group_label(group_rows.first),
              rows: group_rows,
              count: group_rows.size,
              currency_totals: currency_totals_for(group_rows)
            )
          end
          .sort_by { |group| group_rank(group) }
      end

      def ordered_rows = groups.flat_map(&:rows)
      def totals_by_currency = currency_totals_for(rows)
      def group_key_for(row) = group_key(row)

      def subset(booking_ids)
        wanted = Array(booking_ids).map(&:to_i).to_set
        selected_rows = ordered_rows.select { |row| wanted.include?(row.booking_id) }
        self.class.new(
          hotel: @hotel, group_by:, date_preset: @date_preset, rows: selected_rows,
          start_date:, end_date:
        )
      end

      def regroup(grouping)
        self.class.new(
          hotel: @hotel, group_by: grouping, date_preset: @date_preset, rows: rows,
          start_date:, end_date:
        )
      end

      private

      def apply_filters(bookings, filters)
        scope = bookings
        {
          source: filters[:booking_sources],
          status: filters[:statuses],
          payment_status: filters[:payment_statuses],
          currency: filters[:currencies]
        }.each do |column, selected|
          next if selected.nil?

          scope = selected.empty? ? scope.none : scope.where(column => selected)
        end
        scope
      end

      # The collector key can name an online travel agency, and no column holds
      # that key, so the report filters this one column on the built rows.
      def select_collectors(built, selected)
        return built if selected.nil?
        return [] if selected.empty?

        built.select { |row| selected.include?(row.fund_collector) }
      end

      def build_filter_options(bookings)
        {
          booking_sources: options_for(bookings, :source, &method(:source_label)),
          fund_collectors: collector_options(bookings),
          statuses: options_for(bookings, :status, &method(:status_label)),
          payment_statuses: options_for(bookings, :payment_status) { |value| value.to_s.humanize },
          currencies: options_for(bookings, :currency) { |value| value.to_s.upcase }
        }
      end

      def options_for(bookings, column)
        bookings.reorder(nil).distinct.pluck(column).compact_blank
          .map { |value| [ yield(value), value.to_s ] }
          .sort_by { |label, _value| label.downcase }
      end

      def collector_options(bookings)
        bookings.reorder(nil).distinct.pluck(:fund_collector, :source)
          .map { |collector, source| collector_key(collector, source) }
          .uniq
          .map { |key| [ collector_label(key), key ] }
          .sort_by { |label, _key| label.downcase }
      end

      def empty_filter_options
        { booking_sources: [], fund_collectors: [], statuses: [], payment_statuses: [], currencies: [] }
      end

      def build_rows(bookings)
        bookings.map do |booking|
          source = booking.source.to_s.presence || "unknown"
          collector = collector_key(booking.fund_collector, source)
          currency = booking.currency.to_s.presence || @hotel.default_currency.presence || "MYR"
          Row.new(
            booking_id: booking.id,
            booked_on: booking.created_at.in_time_zone(@hotel.hotel_time_zone).to_date,
            booking_number: booking.formatted_reservation_number,
            confirmation_code: booking.confirmation_token,
            guest_name: booking.guest_name,
            status: booking.status,
            status_label: status_label(booking.status),
            payment_status: booking.payment_status,
            payment_status_label: booking.payment_status.to_s.humanize,
            check_in: booking.check_in.to_date,
            check_out: booking.check_out.to_date,
            source:,
            source_label: source_label(source),
            fund_collector: collector,
            fund_collector_label: collector_label(collector),
            gross: booking.total_amount.to_d,
            taxes: booking.tax_total.to_d,
            commission: booking.margin_amount.to_d,
            net: booking.net_amount.to_d,
            currency:
          )
        end
      end

      def group_key(row)
        case group_by
        when "source" then row.source
        when "fund_collector" then row.fund_collector
        when "status" then row.status
        when "currency" then row.currency
        else booking_period(row.booked_on).iso8601
        end
      end

      def group_label(row)
        case group_by
        when "source" then row.source_label
        when "fund_collector" then row.fund_collector_label
        when "status" then row.status_label
        when "currency" then row.currency
        else booking_period(row.booked_on).strftime(monthly? ? "%B %Y" : "%d %b %Y")
        end
      end

      def group_rank(group)
        case group_by
        when "booking_date" then [ -Date.iso8601(group.key).jd ]
        when "fund_collector" then [ collector_rank(group.key), group.label.downcase ]
        else [ group.label.downcase ]
        end
      end

      # WAStays first, then the hotel, then every agency, and the unknown last.
      def collector_rank(key)
        COLLECTOR_ORDER.index(key) || (key == "unknown" ? UNKNOWN_COLLECTOR_RANK : COLLECTOR_ORDER.size)
      end

      def booking_period(date) = monthly? ? date.beginning_of_month : date
      def monthly? = @date_preset == "this_year"

      def currency_totals_for(selected_rows)
        selected_rows.group_by(&:currency).sort_by(&:first).map do |currency, currency_rows|
          {
            currency:,
            booking_count: currency_rows.size,
            gross: currency_rows.sum(&:gross).round(2),
            taxes: currency_rows.sum(&:taxes).round(2),
            commission: currency_rows.sum(&:commission).round(2),
            net: currency_rows.sum(&:net).round(2)
          }.freeze
        end.freeze
      end

      # An online travel agency takes the money itself, so a channel booking that
      # names no collector is collected by that agency. A direct payment at the
      # hotel still sets the collector, and that answer wins.
      def collector_key(stored, source)
        collector = stored.to_s.presence || "unknown"
        return collector unless collector == "unknown"

        record = BookingSource.find_by_source(source)
        return collector unless record&.kind == "ota"

        "#{OTA_COLLECTOR_PREFIX}#{record.key}"
      end

      def source_label(value)
        BookingSource.find_by_source(value)&.label ||
          DailyRevenueReport::SOURCE_LABELS[value.to_s] ||
          value.to_s.humanize.presence || "Unknown"
      end

      def collector_label(value)
        key = value.to_s
        return source_label(key.delete_prefix(OTA_COLLECTOR_PREFIX)) if key.start_with?(OTA_COLLECTOR_PREFIX)

        { "wastays" => "WAStays", "hotel" => "Hotel", "unknown" => "Unknown" }.fetch(key) do
          key.humanize.presence || "Unknown"
        end
      end

      def status_label(value)
        HotelPortal::BookingFinancialPresenter::STATUS_PRESENTATION
          .fetch(value.to_s, { label: value.to_s.humanize.presence || "Unknown" })
          .fetch(:label)
      end
    end
  end
end
